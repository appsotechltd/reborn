package api

import (
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/url"

	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Gifts support the platform. The web pays through Stripe Checkout; the apps
// pay with Apple or Google in-app purchases, which the server verifies.

func (s *Server) giftTiers(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"tiers":     payments.Tiers,
		"providers": map[string]bool{"stripe": s.Stripe != nil, "apple": s.Apple != nil, "google": s.Google != nil},
	})
}

func (s *Server) giftTier(w http.ResponseWriter, id string) (payments.Tier, bool) {
	t, ok := payments.TierByID(id)
	if !ok {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown gift tier")
	}
	return t, ok
}

func (s *Server) giftCheckout(w http.ResponseWriter, r *http.Request) {
	if s.Stripe == nil {
		writeError(w, http.StatusServiceUnavailable, "gifts_unavailable", "web gifts are not set up yet")
		return
	}
	var in struct {
		Tier string `json:"tier"`
	}
	if !decode(w, r, &in) {
		return
	}
	tier, ok := s.giftTier(w, in.Tier)
	if !ok {
		return
	}
	post, err := s.Store.GetPost(r.Context(), r.PathValue("id"), "")
	if err != nil {
		s.fail(w, r, err, "post")
		return
	}
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	g, err := s.Store.CreatePendingGift(r.Context(), store.NewGift{UserID: u.ID, PostID: post.ID, Tier: tier.ID,
		AmountCents: tier.AmountCents, Currency: tier.Currency, Provider: "stripe"})
	if err != nil {
		s.fail(w, r, err, "gift")
		return
	}
	back := s.WebBaseURL + "/ideas/" + url.PathEscape(post.ID)
	sessionID, checkoutURL, err := s.Stripe.CreateCheckout(r.Context(), payments.CheckoutRequest{
		GiftID: g.ID, Tier: tier, PostTitle: post.Card.Title, Email: u.Email,
		SuccessURL: back + "?gift=" + g.ID, CancelURL: back,
	})
	if err != nil {
		slog.Error("stripe checkout", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't start the payment, try again")
		return
	}
	if err := s.Store.SetGiftRef(r.Context(), g.ID, sessionID); err != nil {
		s.fail(w, r, err, "gift")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"gift_id": g.ID, "url": checkoutURL})
}

func (s *Server) stripeWebhook(w http.ResponseWriter, r *http.Request) {
	if s.Stripe == nil {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	payload, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "unreadable body")
		return
	}
	ev, err := s.Stripe.VerifyWebhook(payload, r.Header.Get("Stripe-Signature"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_signature", "signature check failed")
		return
	}
	obj := ev.Data.Object
	switch ev.Type {
	case "checkout.session.completed", "checkout.session.async_payment_succeeded":
		if obj.PaymentStatus == "paid" && obj.Metadata["gift_id"] != "" {
			if err := s.Store.MarkGiftPaid(r.Context(), obj.Metadata["gift_id"], "stripe", obj.ID, s.Now()); err != nil {
				s.fail(w, r, err, "gift")
				return
			}
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) giftApple(w http.ResponseWriter, r *http.Request) {
	if s.Apple == nil {
		writeError(w, http.StatusServiceUnavailable, "gifts_unavailable", "App Store gifts are not set up yet")
		return
	}
	var in struct {
		SignedTransaction string `json:"signed_transaction"`
	}
	if !decode(w, r, &in) {
		return
	}
	tx, err := s.Apple.VerifyTransaction(in.SignedTransaction)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the purchase could not be verified")
		return
	}
	s.recordStoreGift(w, r, "apple", tx.ProductID, tx.TransactionID)
}

func (s *Server) giftGoogle(w http.ResponseWriter, r *http.Request) {
	if s.Google == nil {
		writeError(w, http.StatusServiceUnavailable, "gifts_unavailable", "Google Play gifts are not set up yet")
		return
	}
	var in struct {
		ProductID     string `json:"product_id"`
		PurchaseToken string `json:"purchase_token"`
	}
	if !decode(w, r, &in) {
		return
	}
	if _, ok := payments.TierByProduct(in.ProductID); !ok || in.PurchaseToken == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown product or missing purchase token")
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
	s.recordStoreGift(w, r, "google", in.ProductID, p.OrderID)
}

func (s *Server) recordStoreGift(w http.ResponseWriter, r *http.Request, provider, productID, ref string) {
	tier, ok := payments.TierByProduct(productID)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "unknown product")
		return
	}
	g, err := s.Store.RecordPaidGift(r.Context(), store.NewGift{UserID: userID(r), PostID: r.PathValue("id"), Tier: tier.ID,
		AmountCents: tier.AmountCents, Currency: tier.Currency, Provider: provider}, ref, s.Now())
	if err != nil {
		s.fail(w, r, err, "post")
		return
	}
	writeJSON(w, http.StatusCreated, g)
}

func (s *Server) gift(w http.ResponseWriter, r *http.Request) {
	g, err := s.Store.GetGift(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "gift")
		return
	}
	writeJSON(w, http.StatusOK, g)
}
