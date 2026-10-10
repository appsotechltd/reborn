package store

import (
	"context"
	"time"
)

// Gift is one gift on a post.
type Gift struct {
	ID          string     `json:"id"`
	PostID      string     `json:"post_id"`
	Tier        string     `json:"tier"`
	AmountCents int        `json:"amount_cents"`
	Currency    string     `json:"currency"`
	Provider    string     `json:"provider"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	PaidAt      *time.Time `json:"paid_at"`
}

const giftCols = `id::text, card_id, tier, amount_cents, currency, provider, status, created_at, paid_at`

func scanGift(row interface{ Scan(...any) error }) (Gift, error) {
	var g Gift
	err := row.Scan(&g.ID, &g.PostID, &g.Tier, &g.AmountCents, &g.Currency, &g.Provider, &g.Status, &g.CreatedAt, &g.PaidAt)
	return g, err
}

// NewGift is a gift to record.
type NewGift struct {
	UserID      string
	PostID      string
	Tier        string
	AmountCents int
	Currency    string
	Provider    string
}

// CreatePendingGift records a gift whose payment has started but not finished.
func (s *Store) CreatePendingGift(ctx context.Context, g NewGift) (Gift, error) {
	if err := s.postExists(ctx, g.PostID); err != nil {
		return Gift{}, err
	}
	return scanGift(s.DB.QueryRow(ctx, `INSERT INTO gifts (user_id, card_id, tier, amount_cents, currency, provider)
		VALUES ($1, $2, $3, $4, $5, $6) RETURNING `+giftCols, g.UserID, g.PostID, g.Tier, g.AmountCents, g.Currency, g.Provider))
}

// SetGiftRef stores the payment provider's id for a pending gift.
func (s *Store) SetGiftRef(ctx context.Context, id, ref string) error {
	_, err := s.DB.Exec(ctx, `UPDATE gifts SET provider_ref = $2 WHERE id::text = $1`, id, ref)
	return err
}

// MarkGiftPaid marks a pending gift as paid. Repeated calls are harmless.
func (s *Store) MarkGiftPaid(ctx context.Context, id, provider, ref string, now time.Time) error {
	_, err := s.DB.Exec(ctx, `UPDATE gifts SET status = 'paid', paid_at = $4, provider_ref = coalesce(provider_ref, $3)
		WHERE id::text = $1 AND provider = $2 AND status = 'pending'`, id, provider, ref, now)
	return err
}

// RecordPaidGift stores a gift that a store already confirmed. The same store
// transaction is only ever counted once; a repeat returns the first gift.
func (s *Store) RecordPaidGift(ctx context.Context, g NewGift, ref string, now time.Time) (Gift, error) {
	if err := s.postExists(ctx, g.PostID); err != nil {
		return Gift{}, err
	}
	_, err := s.DB.Exec(ctx, `INSERT INTO gifts (user_id, card_id, tier, amount_cents, currency, provider, provider_ref, status, paid_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'paid', $8) ON CONFLICT (provider, provider_ref) DO NOTHING`,
		g.UserID, g.PostID, g.Tier, g.AmountCents, g.Currency, g.Provider, ref, now)
	if err != nil {
		return Gift{}, err
	}
	return scanGift(s.DB.QueryRow(ctx, `SELECT `+giftCols+` FROM gifts WHERE provider = $1 AND provider_ref = $2`, g.Provider, ref))
}

// GetGift returns a gift the user gave.
func (s *Store) GetGift(ctx context.Context, userID, id string) (Gift, error) {
	g, err := scanGift(s.DB.QueryRow(ctx, `SELECT `+giftCols+` FROM gifts WHERE id::text = $1 AND user_id = $2`, id, userID))
	return g, notFound(err)
}
