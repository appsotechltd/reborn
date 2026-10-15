package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
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
	// AuthorCents is the writer's share of a gift on a member's card.
	AuthorCents int `json:"author_cents"`
}

const giftCols = `id::text, card_id, tier, amount_cents, currency, provider, status, created_at, paid_at, author_cents`

func scanGift(row interface{ Scan(...any) error }) (Gift, error) {
	var g Gift
	err := row.Scan(&g.ID, &g.PostID, &g.Tier, &g.AmountCents, &g.Currency, &g.Provider, &g.Status, &g.CreatedAt, &g.PaidAt, &g.AuthorCents)
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
	// Set for gifts on a member's card: the writer, the payment fee and their share.
	AuthorID    string
	FeeCents    int
	AuthorCents int
}

// CreatePendingGift records a gift whose payment has started but not finished.
func (s *Store) CreatePendingGift(ctx context.Context, g NewGift) (Gift, error) {
	if err := s.postExists(ctx, g.PostID); err != nil {
		return Gift{}, err
	}
	return scanGift(s.DB.QueryRow(ctx, `INSERT INTO gifts (user_id, card_id, tier, amount_cents, currency, provider, author_id, fee_cents, author_cents)
		VALUES ($1, $2, $3, $4, $5, $6, $7::uuid, $8, $9) RETURNING `+giftCols,
		g.UserID, g.PostID, g.Tier, g.AmountCents, g.Currency, g.Provider, nullable(g.AuthorID), g.FeeCents, g.AuthorCents))
}

// SetGiftRef stores the payment provider's id for a pending gift.
func (s *Store) SetGiftRef(ctx context.Context, id, ref string) error {
	_, err := s.DB.Exec(ctx, `UPDATE gifts SET provider_ref = $2 WHERE id::text = $1`, id, ref)
	return err
}

// MarkGiftPaid marks a pending gift as paid. Repeated calls are harmless.
// It returns the gift when this call marked it paid, so the writer can be told once.
func (s *Store) MarkGiftPaid(ctx context.Context, id, provider, ref string, now time.Time) (*PaidGift, error) {
	var p PaidGift
	err := s.DB.QueryRow(ctx, `UPDATE gifts SET status = 'paid', paid_at = $4, provider_ref = coalesce(provider_ref, $3)
		WHERE id::text = $1 AND provider = $2 AND status = 'pending'
		RETURNING card_id, coalesce(user_id::text, ''), coalesce(author_id::text, ''), author_cents`, id, provider, ref, now).
		Scan(&p.PostID, &p.GiverID, &p.AuthorID, &p.AuthorCents)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}

// PaidGift is a gift that has just been paid.
type PaidGift struct {
	PostID      string
	GiverID     string
	AuthorID    string
	AuthorCents int
}

// RecordPaidGift stores a gift that a store already confirmed. The same store
// transaction is only ever counted once; a repeat returns the first gift, and
// isNew is false.
func (s *Store) RecordPaidGift(ctx context.Context, g NewGift, ref string, now time.Time) (gift Gift, isNew bool, err error) {
	if err := s.postExists(ctx, g.PostID); err != nil {
		return Gift{}, false, err
	}
	tag, err := s.DB.Exec(ctx, `INSERT INTO gifts (user_id, card_id, tier, amount_cents, currency, provider, provider_ref, status, paid_at,
			author_id, fee_cents, author_cents)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'paid', $8, $9::uuid, $10, $11) ON CONFLICT (provider, provider_ref) DO NOTHING`,
		g.UserID, g.PostID, g.Tier, g.AmountCents, g.Currency, g.Provider, ref, now, nullable(g.AuthorID), g.FeeCents, g.AuthorCents)
	if err != nil {
		return Gift{}, false, err
	}
	out, err := scanGift(s.DB.QueryRow(ctx, `SELECT `+giftCols+` FROM gifts WHERE provider = $1 AND provider_ref = $2`, g.Provider, ref))
	return out, tag.RowsAffected() == 1, err
}

// Earning is one gift or subscription payment a writer received.
type Earning struct {
	Kind        string    `json:"kind"`       // gift or subscription
	PostID      string    `json:"post_id"`    // gifts only
	PostTitle   string    `json:"post_title"` // gifts only
	Tier        string    `json:"tier"`
	AmountCents int       `json:"amount_cents"`
	AuthorCents int       `json:"author_cents"`
	Currency    string    `json:"currency"`
	From        *Profile  `json:"from"`
	PaidAt      time.Time `json:"paid_at"`
}

// Earnings is what a writer has earned from gifts on their cards.
type Earnings struct {
	TotalCents     int       `json:"total_cents"`
	ThisMonthCents int       `json:"this_month_cents"`
	Gifts          int       `json:"gifts"`
	Subscribers    int       `json:"subscribers"` // live subscriptions now
	Currency       string    `json:"currency"`
	Recent         []Earning `json:"recent"`
}

// earningRows are every payment a writer gets a share of.
const earningRows = `SELECT 'gift' AS kind, g.card_id AS post_id, c.title AS post_title, g.tier, g.amount_cents, g.author_cents, g.currency,
		g.paid_at, g.user_id AS from_id
	FROM gifts g JOIN cards c ON c.id = g.card_id WHERE g.author_id = $1 AND g.status = 'paid'
	UNION ALL
	SELECT 'subscription', '', '', p.tier, p.amount_cents, p.author_cents, p.currency, p.paid_at, p.subscriber_id
	FROM writer_payments p WHERE p.writer_id = $1`

// EarningsOf adds up the writer's share of gifts on their cards and of their subscriptions.
func (s *Store) EarningsOf(ctx context.Context, authorID string, now time.Time) (Earnings, error) {
	e := Earnings{Currency: "usd", Recent: []Earning{}}
	if err := s.DB.QueryRow(ctx, `SELECT coalesce(sum(author_cents), 0)::int, coalesce(sum(author_cents) FILTER (WHERE paid_at >= $2), 0)::int,
			count(*) FILTER (WHERE kind = 'gift')::int,
			(SELECT count(*) FROM writer_subscriptions WHERE writer_id = $1 AND expires_at > $3)::int
		FROM (`+earningRows+`) x`, authorID, monthStart(now), now).Scan(&e.TotalCents, &e.ThisMonthCents, &e.Gifts, &e.Subscribers); err != nil {
		return e, err
	}
	rows, err := s.DB.Query(ctx, `SELECT x.kind, x.post_id, x.post_title, x.tier, x.amount_cents, x.author_cents, x.currency, x.paid_at,
			u.id::text, u.handle, u.display_name
		FROM (`+earningRows+`) x LEFT JOIN users u ON u.id = x.from_id ORDER BY x.paid_at DESC LIMIT 50`, authorID)
	if err != nil {
		return e, err
	}
	defer rows.Close()
	for rows.Next() {
		var x Earning
		var uid, handle, name *string
		if err := rows.Scan(&x.Kind, &x.PostID, &x.PostTitle, &x.Tier, &x.AmountCents, &x.AuthorCents, &x.Currency, &x.PaidAt, &uid, &handle, &name); err != nil {
			return e, err
		}
		if uid != nil {
			x.From = &Profile{ID: *uid, Handle: *handle, DisplayName: *name}
		}
		e.Recent = append(e.Recent, x)
	}
	return e, rows.Err()
}

// GetGift returns a gift the user gave.
func (s *Store) GetGift(ctx context.Context, userID, id string) (Gift, error) {
	g, err := scanGift(s.DB.QueryRow(ctx, `SELECT `+giftCols+` FROM gifts WHERE id::text = $1 AND user_id = $2`, id, userID))
	return g, notFound(err)
}
