package api

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Premium: offline audio, a much higher AI guide limit, and no gift prompts.
// Subscriptions run through Stripe on the web and the app stores on mobile.

// premiumAgentFactor multiplies the hourly AI guide limit for premium members.
const premiumAgentFactor = 10

func (s *Server) premium(w http.ResponseWriter, r *http.Request) {
	out := map[string]any{
		"plans": payments.Plans,
		"providers": map[string]bool{
			"stripe": s.Stripe != nil && len(s.StripePrices) > 0, "apple": s.Apple != nil, "google": s.Google != nil,
		},
		"premium": false, "premium_until": nil, "subscription": nil,
	}
	if uid := userID(r); uid != "" {
		u, err := s.Store.UserByID(r.Context(), uid)
		if err != nil {
			s.fail(w, r, err, "user")
			return
		}
		sub, err := s.Store.ActiveSubscription(r.Context(), uid, s.Now())
		if err != nil {
			s.fail(w, r, err, "subscription")
			return
		}
		out["premium"], out["premium_until"] = u.Premium, u.PremiumUntil
		if sub != nil {
			out["subscription"] = map[string]any{"provider": sub.Provider, "plan": sub.Plan, "status": sub.Status, "expires_at": sub.ExpiresAt}
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) premiumCheckout(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Plan string `json:"plan"`
	}
	if !decode(w, r, &in) {
		return
	}
	price := s.StripePrices[in.Plan]
	if s.Stripe == nil || price == "" {
		writeError(w, http.StatusServiceUnavailable, "premium_unavailable", "web subscriptions are not set up yet")
		return
	}
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	customer, err := s.Store.StripeCustomer(r.Context(), u.ID)
	if err != nil && err != store.ErrNotFound {
		s.fail(w, r, err, "user")
		return
	}
	checkoutURL, err := s.Stripe.CreateSubscriptionCheckout(r.Context(), payments.SubscriptionCheckout{
		UserID: u.ID, Email: u.Email, Customer: customer, PriceID: price, Plan: in.Plan,
		SuccessURL: s.WebBaseURL + "/premium?welcome=1", CancelURL: s.WebBaseURL + "/premium",
	})
	if err != nil {
		slog.Error("stripe subscription checkout", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't start the payment, try again")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"url": checkoutURL})
}

func (s *Server) premiumPortal(w http.ResponseWriter, r *http.Request) {
	if s.Stripe == nil {
		writeError(w, http.StatusServiceUnavailable, "premium_unavailable", "web subscriptions are not set up yet")
		return
	}
	customer, err := s.Store.StripeCustomer(r.Context(), userID(r))
	if err == store.ErrNotFound {
		writeError(w, http.StatusNotFound, "not_found", "no web subscription on this account")
		return
	}
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	portal, err := s.Stripe.CreatePortal(r.Context(), customer, s.WebBaseURL+"/premium")
	if err != nil {
		slog.Error("stripe portal", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't open billing, try again")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"url": portal})
}

// stripeSubscriptionEvent records a subscription's state from a webhook.
func (s *Server) stripeSubscriptionEvent(r *http.Request, obj payments.EventObject) error {
	uid := obj.Metadata["user_id"]
	if uid == "" {
		var err error
		if uid, err = s.Store.SubscriptionUser(r.Context(), "stripe", obj.ID); err != nil {
			return nil // not ours
		}
	}
	plan := obj.Metadata["plan"]
	if plan == "" {
		plan = "monthly"
	}
	status := obj.Status
	expires := obj.PeriodEnd()
	switch status {
	case "active", "trialing", "past_due", "canceled":
		if status == "canceled" && obj.EndedAt != 0 {
			expires = time.Unix(obj.EndedAt, 0)
		}
	default: // incomplete, incomplete_expired, unpaid, paused
		status = "revoked"
	}
	return s.Store.UpsertSubscription(r.Context(), store.Subscription{UserID: uid, Provider: "stripe", Ref: obj.ID, Plan: plan, Status: status, ExpiresAt: expires})
}

func (s *Server) premiumApple(w http.ResponseWriter, r *http.Request) {
	if s.Apple == nil {
		writeError(w, http.StatusServiceUnavailable, "premium_unavailable", "App Store subscriptions are not set up yet")
		return
	}
	var in struct {
		SignedTransaction string `json:"signed_transaction"`
	}
	if !decode(w, r, &in) {
		return
	}
	tx, err := s.Apple.ParseTransaction(in.SignedTransaction)
	plan, ok := payments.PlanByProduct(tx.ProductID)
	if err != nil || !ok || tx.ExpiresDate == 0 {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the subscription could not be verified")
		return
	}
	s.saveStoreSubscription(w, r, store.Subscription{UserID: userID(r), Provider: "apple", Ref: originalID(tx), Plan: plan.ID,
		Status: appleStatus(tx), ExpiresAt: tx.Expires()})
}

func originalID(tx payments.AppleTransaction) string {
	if tx.OriginalTransactionID != "" {
		return tx.OriginalTransactionID
	}
	return tx.TransactionID
}

func appleStatus(tx payments.AppleTransaction) string {
	if tx.RevocationDate != 0 {
		return "revoked"
	}
	return "active"
}

func (s *Server) premiumGoogle(w http.ResponseWriter, r *http.Request) {
	if s.Google == nil {
		writeError(w, http.StatusServiceUnavailable, "premium_unavailable", "Google Play subscriptions are not set up yet")
		return
	}
	var in struct {
		PurchaseToken string `json:"purchase_token"`
	}
	if !decode(w, r, &in) {
		return
	}
	sub, err := s.Google.VerifySubscription(r.Context(), in.PurchaseToken)
	if errors.Is(err, payments.ErrInvalid) {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the subscription could not be verified")
		return
	}
	if err != nil {
		slog.Error("google play subscription", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't check the subscription, try again")
		return
	}
	plan, ok := payments.PlanByProduct(sub.ProductID)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "unknown subscription product")
		return
	}
	s.saveStoreSubscription(w, r, store.Subscription{UserID: userID(r), Provider: "google", Ref: in.PurchaseToken, Plan: plan.ID,
		Status: googleStatus(sub.State), ExpiresAt: sub.Expires})
}

func googleStatus(state string) string {
	switch state {
	case "SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
		return "active"
	case "SUBSCRIPTION_STATE_CANCELED", "SUBSCRIPTION_STATE_EXPIRED":
		return "canceled"
	default: // on hold, paused, pending
		return "revoked"
	}
}

// saveStoreSubscription stores a verified app store subscription, refusing one
// that already belongs to another account.
func (s *Server) saveStoreSubscription(w http.ResponseWriter, r *http.Request, sub store.Subscription) {
	owner, err := s.Store.SubscriptionUser(r.Context(), sub.Provider, sub.Ref)
	if err == nil && owner != sub.UserID {
		writeError(w, http.StatusConflict, "subscription_taken", "this subscription belongs to another Reborn account")
		return
	}
	if err != nil && err != store.ErrNotFound {
		s.fail(w, r, err, "subscription")
		return
	}
	if err := s.Store.UpsertSubscription(r.Context(), sub); err != nil {
		s.fail(w, r, err, "subscription")
		return
	}
	s.premium(w, r)
}

// appleWebhook receives App Store Server Notifications V2 for renewals,
// expiries and refunds.
func (s *Server) appleWebhook(w http.ResponseWriter, r *http.Request) {
	if s.Apple == nil {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	var in struct {
		SignedPayload string `json:"signedPayload"`
	}
	if !decode(w, r, &in) {
		return
	}
	n, err := s.Apple.VerifyNotification(in.SignedPayload)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_signature", "signature check failed")
		return
	}
	tx := n.Transaction
	plan, isPlan := payments.PlanByProduct(tx.ProductID)
	if !isPlan || tx.ExpiresDate == 0 {
		w.WriteHeader(http.StatusOK) // not a subscription we sell
		return
	}
	ref := originalID(tx)
	uid, err := s.Store.SubscriptionUser(r.Context(), "apple", ref)
	if err == store.ErrNotFound && tx.AppAccountToken != "" {
		if _, uerr := s.Store.UserByID(r.Context(), tx.AppAccountToken); uerr == nil {
			uid, err = tx.AppAccountToken, nil
		}
	}
	if err != nil {
		w.WriteHeader(http.StatusOK) // nobody to credit yet; the app reports the purchase itself
		return
	}
	status := appleStatus(tx)
	if n.Type == "EXPIRED" || (n.Type == "DID_CHANGE_RENEWAL_STATUS" && n.Subtype == "AUTO_RENEW_DISABLED") {
		status = "canceled"
	}
	if n.Type == "REFUND" || n.Type == "REVOKE" {
		status = "revoked"
	}
	if err := s.Store.UpsertSubscription(r.Context(), store.Subscription{UserID: uid, Provider: "apple", Ref: ref, Plan: plan.ID,
		Status: status, ExpiresAt: tx.Expires()}); err != nil {
		s.fail(w, r, err, "subscription")
		return
	}
	w.WriteHeader(http.StatusOK)
}

// googleWebhook receives Play real-time developer notifications through a
// Pub/Sub push subscription whose URL carries ?token=GOOGLE_RTDN_TOKEN.
func (s *Server) googleWebhook(w http.ResponseWriter, r *http.Request) {
	if s.Google == nil || s.GoogleRTDNToken == "" || r.URL.Query().Get("token") != s.GoogleRTDNToken {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	var in struct {
		Message struct {
			Data []byte `json:"data"`
		} `json:"message"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	raw, err := io.ReadAll(r.Body)
	if err != nil || json.Unmarshal(raw, &in) != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "unreadable notification")
		return
	}
	var note struct {
		SubscriptionNotification *struct {
			PurchaseToken string `json:"purchaseToken"`
		} `json:"subscriptionNotification"`
	}
	if json.Unmarshal(in.Message.Data, &note) != nil || note.SubscriptionNotification == nil {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	token := note.SubscriptionNotification.PurchaseToken
	sub, err := s.Google.VerifySubscription(r.Context(), token)
	if err != nil {
		slog.Warn("google rtdn verify", "err", err)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	plan, ok := payments.PlanByProduct(sub.ProductID)
	if !ok {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	uid, err := s.Store.SubscriptionUser(r.Context(), "google", token)
	if err == store.ErrNotFound && sub.AccountID != "" {
		if _, uerr := s.Store.UserByID(r.Context(), sub.AccountID); uerr == nil {
			uid, err = sub.AccountID, nil
		}
	}
	if err == nil {
		err = s.Store.UpsertSubscription(r.Context(), store.Subscription{UserID: uid, Provider: "google", Ref: token, Plan: plan.ID,
			Status: googleStatus(sub.State), ExpiresAt: sub.Expires})
	}
	if err != nil && err != store.ErrNotFound {
		slog.Error("google rtdn", "err", err)
	}
	w.WriteHeader(http.StatusNoContent)
}
