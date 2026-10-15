package api

import (
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Writers can sell monthly subscriptions. Subscribers read the writer's
// subscribers-only (and followers-only) cards. The payment fee comes off
// first, then Reborn keeps GiftCommission percent, as with gifts.

func (s *Server) myPlan(w http.ResponseWriter, r *http.Request) {
	out := map[string]any{"plan": nil, "tiers": payments.WriterTiers, "commission_percent": s.GiftCommission, "store_fee_percent": s.StoreFee}
	p, err := s.Store.WriterPlanOf(r.Context(), userID(r), s.Now())
	if err == nil {
		out["plan"] = p
	} else if !errors.Is(err, store.ErrNotFound) {
		s.fail(w, r, err, "plan")
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) setMyPlan(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Tier    string `json:"tier"`
		Enabled bool   `json:"enabled"`
		Pitch   string `json:"pitch"`
	}
	if !decode(w, r, &in) {
		return
	}
	if _, ok := payments.WriterTierByID(in.Tier); !ok {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown price")
		return
	}
	in.Pitch = strings.TrimSpace(in.Pitch)
	if utf8.RuneCountInString(in.Pitch) > 300 {
		writeError(w, http.StatusBadRequest, "bad_request", "the pitch must be at most 300 characters")
		return
	}
	p, err := s.Store.SetWriterPlan(r.Context(), userID(r), in.Tier, in.Enabled, in.Pitch, s.Now())
	if err != nil {
		s.fail(w, r, err, "plan")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

// writerOffer returns a writer's profile and their plan's price, when they sell subscriptions.
func (s *Server) writerOffer(w http.ResponseWriter, r *http.Request) (store.UserProfile, *store.WriterPlan, *payments.WriterTier, bool) {
	prof, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return prof, nil, nil, false
	}
	p, err := s.Store.WriterPlanOf(r.Context(), prof.ID, s.Now())
	if errors.Is(err, store.ErrNotFound) || (err == nil && !p.Enabled) {
		return prof, nil, nil, true
	}
	if err != nil {
		s.fail(w, r, err, "plan")
		return prof, nil, nil, false
	}
	tier, ok := payments.WriterTierByID(p.Tier)
	if !ok {
		return prof, nil, nil, true
	}
	return prof, &p, &tier, true
}

func (s *Server) userPlan(w http.ResponseWriter, r *http.Request) {
	prof, plan, tier, ok := s.writerOffer(w, r)
	if !ok {
		return
	}
	locked, err := s.Store.LockedCards(r.Context(), prof.ID, userID(r))
	if err != nil {
		s.fail(w, r, err, "cards")
		return
	}
	out := map[string]any{"plan": nil, "tier": nil, "locked_cards": locked, "subscription": nil,
		"providers": map[string]bool{"stripe": s.Stripe != nil, "apple": s.Apple != nil, "google": s.Google != nil}}
	if plan != nil {
		out["plan"], out["tier"] = map[string]any{"pitch": plan.Pitch, "subscribers": plan.Subscribers}, tier
	}
	if uid := userID(r); uid != "" {
		sub, err := s.Store.WriterSubscriptionOf(r.Context(), uid, prof.ID, s.Now())
		if err == nil {
			out["subscription"] = sub
		} else if !errors.Is(err, store.ErrNotFound) {
			s.fail(w, r, err, "subscription")
			return
		}
	}
	writeJSON(w, http.StatusOK, out)
}

// subscribable checks the writer sells subscriptions and the member isn't subscribing to themself.
func (s *Server) subscribable(w http.ResponseWriter, r *http.Request) (store.UserProfile, payments.WriterTier, bool) {
	prof, plan, tier, ok := s.writerOffer(w, r)
	if !ok {
		return prof, payments.WriterTier{}, false
	}
	if plan == nil {
		writeError(w, http.StatusNotFound, "no_plan", "this writer doesn't offer subscriptions")
		return prof, payments.WriterTier{}, false
	}
	if prof.IsMe {
		writeError(w, http.StatusBadRequest, "own_page", "you can't subscribe to yourself")
		return prof, payments.WriterTier{}, false
	}
	return prof, *tier, true
}

func (s *Server) writerPayment(prof store.UserProfile, uid string, tier payments.WriterTier, provider, ref string) store.WriterPayment {
	split := payments.SplitGift(tier.AmountCents, provider, s.GiftCommission, s.StoreFee)
	return store.WriterPayment{WriterID: prof.ID, SubscriberID: uid, Tier: tier.ID, AmountCents: tier.AmountCents, Currency: tier.Currency,
		FeeCents: split.FeeCents, AuthorCents: split.AuthorCents, Provider: provider, Ref: ref}
}

func (s *Server) newSubscriber(writerID, subscriberID string) {
	s.notify(store.NewNotification{UserID: writerID, Kind: "subscriber", ActorID: subscriberID, Text: "You have a new subscriber."},
		"gifts", map[string]string{})
}

func (s *Server) subscribeCheckout(w http.ResponseWriter, r *http.Request) {
	if s.Stripe == nil {
		writeError(w, http.StatusServiceUnavailable, "subscriptions_unavailable", "web subscriptions are not set up yet")
		return
	}
	prof, tier, ok := s.subscribable(w, r)
	if !ok {
		return
	}
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	back := s.WebBaseURL + "/u/" + url.PathEscape(prof.Handle)
	checkoutURL, err := s.Stripe.CreateWriterCheckout(r.Context(), payments.WriterCheckout{SubscriberID: u.ID, WriterID: prof.ID,
		WriterName: prof.DisplayName, Tier: tier, Email: u.Email, SuccessURL: back + "?subscribed=1", CancelURL: back})
	if err != nil {
		slog.Error("stripe writer checkout", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't start the payment, try again")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"url": checkoutURL})
}

// stripeWriterEvent handles a subscription event for a writer subscription.
func (s *Server) stripeWriterEvent(r *http.Request, obj payments.EventObject) error {
	md := obj.Metadata
	tier, ok := payments.WriterTierByID(md["tier"])
	if !ok || md["subscriber_id"] == "" || md["writer_id"] == "" {
		return nil
	}
	expires := obj.PeriodEnd()
	if obj.Status == "canceled" && obj.EndedAt != 0 {
		expires = time.Unix(obj.EndedAt, 0)
	}
	live := obj.Status == "active" || obj.Status == "past_due"
	if !live && obj.Status != "canceled" {
		expires = s.Now() // incomplete, unpaid or paused: no access
	}
	prof := store.UserProfile{Profile: store.Profile{ID: md["writer_id"]}}
	p := s.writerPayment(prof, md["subscriber_id"], tier, "stripe", obj.ID)
	paid, err := s.Store.UpsertStripeWriterSub(r.Context(), store.StripeWriterEvent{Payment: p,
		Renews: live && !obj.CancelAtPeriodEnd, Paid: obj.Status == "active", ExpiresAt: expires}, s.Now())
	if err == nil && paid && obj.Status == "active" {
		s.newSubscriber(p.WriterID, p.SubscriberID)
	}
	return err
}

func (s *Server) subscribeApple(w http.ResponseWriter, r *http.Request) {
	if s.Apple == nil {
		writeError(w, http.StatusServiceUnavailable, "subscriptions_unavailable", "App Store subscriptions are not set up yet")
		return
	}
	var in struct {
		SignedTransaction string `json:"signed_transaction"`
	}
	if !decode(w, r, &in) {
		return
	}
	prof, tier, ok := s.subscribable(w, r)
	if !ok {
		return
	}
	tx, err := s.Apple.VerifyTransaction(in.SignedTransaction)
	if err != nil || tx.ProductID != tier.ProductID {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the purchase could not be verified")
		return
	}
	s.recordPass(w, r, prof, tier, "apple", tx.TransactionID)
}

func (s *Server) subscribeGoogle(w http.ResponseWriter, r *http.Request) {
	if s.Google == nil {
		writeError(w, http.StatusServiceUnavailable, "subscriptions_unavailable", "Google Play subscriptions are not set up yet")
		return
	}
	var in struct {
		ProductID     string `json:"product_id"`
		PurchaseToken string `json:"purchase_token"`
	}
	if !decode(w, r, &in) {
		return
	}
	prof, tier, ok := s.subscribable(w, r)
	if !ok {
		return
	}
	if in.ProductID != tier.ProductID || in.PurchaseToken == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "wrong product or missing purchase token")
		return
	}
	p, err := s.Google.VerifyPurchase(r.Context(), in.ProductID, in.PurchaseToken)
	if errors.Is(err, payments.ErrInvalid) {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the purchase could not be verified")
		return
	}
	if err != nil {
		slog.Error("google play verify", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't check the purchase, try again")
		return
	}
	s.recordPass(w, r, prof, tier, "google", p.OrderID)
}

func (s *Server) recordPass(w http.ResponseWriter, r *http.Request, prof store.UserProfile, tier payments.WriterTier, provider, ref string) {
	if ref == "" {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the purchase could not be verified")
		return
	}
	uid := userID(r)
	isNew, err := s.Store.AddWriterPass(r.Context(), s.writerPayment(prof, uid, tier, provider, ref), payments.WriterPassDays, s.Now())
	if err != nil {
		s.fail(w, r, err, "subscription")
		return
	}
	if isNew {
		s.newSubscriber(prof.ID, uid)
	}
	sub, err := s.Store.WriterSubscriptionOf(r.Context(), uid, prof.ID, s.Now())
	if err != nil {
		s.fail(w, r, err, "subscription")
		return
	}
	writeJSON(w, http.StatusCreated, sub)
}

// cancelSubscription stops a web subscription renewing. In-app passes don't renew.
func (s *Server) cancelSubscription(w http.ResponseWriter, r *http.Request) {
	prof, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	sub, err := s.Store.WriterSubscriptionOf(r.Context(), userID(r), prof.ID, s.Now())
	if err != nil {
		s.fail(w, r, err, "subscription")
		return
	}
	if sub.Renews && sub.StripeRef() != "" {
		if s.Stripe == nil {
			writeError(w, http.StatusServiceUnavailable, "subscriptions_unavailable", "web subscriptions are not set up yet")
			return
		}
		if err := s.Stripe.CancelAtPeriodEnd(r.Context(), sub.StripeRef()); err != nil {
			slog.Error("stripe cancel", "err", err)
			writeError(w, http.StatusBadGateway, "payment_error", "couldn't cancel right now, try again")
			return
		}
		if err := s.Store.SetWriterSubRenews(r.Context(), userID(r), prof.ID, false); err != nil {
			s.fail(w, r, err, "subscription")
			return
		}
		sub.Renews = false
	}
	writeJSON(w, http.StatusOK, sub)
}

func (s *Server) mySubscriptions(w http.ResponseWriter, r *http.Request) {
	subs, err := s.Store.MyWriterSubscriptions(r.Context(), userID(r), s.Now())
	if err != nil {
		s.fail(w, r, err, "subscriptions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"subscriptions": subs})
}
