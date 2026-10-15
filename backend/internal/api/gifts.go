package api

import (
	"errors"
	"fmt"
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
		// Gifts on a member's card go to the writer, less the payment fee and this commission.
		"commission_percent": s.GiftCommission,
	})
}

// newGift describes a gift on post. On a member's card the writer gets their share.
func (s *Server) newGift(post store.Post, uid string, tier payments.Tier, provider string) store.NewGift {
	g := store.NewGift{UserID: uid, PostID: post.ID, Tier: tier.ID, AmountCents: tier.AmountCents, Currency: tier.Currency, Provider: provider}
	if a := post.Card.Author; a != nil {
		split := payments.SplitGift(tier.AmountCents, provider, s.GiftCommission, s.StoreFee)
		g.AuthorID, g.FeeCents, g.AuthorCents = a.ID, split.FeeCents, split.AuthorCents
	}
	return g
}

// ownCard refuses a gift on the giver's own card.
func ownCard(w http.ResponseWriter, post store.Post, uid string) bool {
	if post.Card.Author != nil && post.Card.Author.ID == uid {
		writeError(w, http.StatusBadRequest, "own_card", "you can't send a gift to your own card")
		return true
	}
	return false
}

// giftPaid tells the writer of a member card about a gift.
func (s *Server) giftPaid(p *store.PaidGift) {
	if p == nil || p.AuthorID == "" || p.AuthorID == p.GiverID {
		return
	}
	text := fmt.Sprintf("Someone sent a gift for your card. Your share is $%d.%02d.", p.AuthorCents/100, p.AuthorCents%100)
	s.notify(store.NewNotification{UserID: p.AuthorID, Kind: "gift", ActorID: p.GiverID, PostID: p.PostID, Text: text},
		"gifts", map[string]string{"post_id": p.PostID})
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
	if ownCard(w, post, u.ID) {
		return
	}
	g, err := s.Store.CreatePendingGift(r.Context(), s.newGift(post, u.ID, tier, "stripe"))
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
		if obj.Mode == "subscription" && obj.Metadata["user_id"] != "" && obj.Customer != "" {
			if err := s.Store.SetStripeCustomer(r.Context(), obj.Metadata["user_id"], obj.Customer); err != nil {
				s.fail(w, r, err, "user")
				return
			}
		}
		if obj.PaymentStatus == "paid" && obj.Metadata["gift_id"] != "" {
			paid, err := s.Store.MarkGiftPaid(r.Context(), obj.Metadata["gift_id"], "stripe", obj.ID, s.Now())
			if err != nil {
				s.fail(w, r, err, "gift")
				return
			}
			s.giftPaid(paid)
		}
		if obj.PaymentStatus == "paid" && obj.Metadata["topup_id"] != "" {
			if err := s.Store.MarkTopUpPaid(r.Context(), obj.Metadata["topup_id"], "stripe", obj.ID, s.Now()); err != nil {
				s.fail(w, r, err, "top-up")
				return
			}
		}
	case "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted":
		handle := s.stripeSubscriptionEvent
		if obj.Metadata["kind"] == "writer" {
			handle = s.stripeWriterEvent
		}
		if err := handle(r, obj); err != nil {
			s.fail(w, r, err, "subscription")
			return
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
	post, err := s.Store.GetPost(r.Context(), r.PathValue("id"), "")
	if err != nil {
		s.fail(w, r, err, "post")
		return
	}
	uid := userID(r)
	if ownCard(w, post, uid) {
		return
	}
	g, isNew, err := s.Store.RecordPaidGift(r.Context(), s.newGift(post, uid, tier, provider), ref, s.Now())
	if err != nil {
		s.fail(w, r, err, "post")
		return
	}
	if isNew {
		s.giftPaid(&store.PaidGift{PostID: g.PostID, GiverID: uid, AuthorID: authorOf(post), AuthorCents: g.AuthorCents})
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

func authorOf(post store.Post) string {
	if post.Card.Author != nil {
		return post.Card.Author.ID
	}
	return ""
}

func (s *Server) earnings(w http.ResponseWriter, r *http.Request) {
	e, err := s.Store.EarningsOf(r.Context(), userID(r), s.Now())
	if err != nil {
		s.fail(w, r, err, "earnings")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"earnings": e, "commission_percent": s.GiftCommission, "store_fee_percent": s.StoreFee})
}
