package store

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// WriterPlan is a writer's paid subscription offer.
type WriterPlan struct {
	Tier        string    `json:"tier"`
	Enabled     bool      `json:"enabled"`
	Pitch       string    `json:"pitch"`
	Subscribers int       `json:"subscribers"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// WriterPlanOf returns the writer's plan, or ErrNotFound when they never set one.
func (s *Store) WriterPlanOf(ctx context.Context, writerID string, now time.Time) (WriterPlan, error) {
	var p WriterPlan
	err := s.DB.QueryRow(ctx, `SELECT tier, enabled, pitch, updated_at,
			(SELECT count(*) FROM writer_subscriptions ws WHERE ws.writer_id = wp.user_id AND ws.expires_at > $2)
		FROM writer_plans wp WHERE user_id::text = $1`, writerID, now).Scan(&p.Tier, &p.Enabled, &p.Pitch, &p.UpdatedAt, &p.Subscribers)
	return p, notFound(err)
}

// SetWriterPlan saves the writer's plan. Turning it off stops new
// subscriptions; people already subscribed keep access until they lapse.
func (s *Store) SetWriterPlan(ctx context.Context, writerID, tier string, enabled bool, pitch string, now time.Time) (WriterPlan, error) {
	if _, err := s.DB.Exec(ctx, `INSERT INTO writer_plans (user_id, tier, enabled, pitch) VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id) DO UPDATE SET tier = EXCLUDED.tier, enabled = EXCLUDED.enabled, pitch = EXCLUDED.pitch, updated_at = now()`,
		writerID, tier, enabled, pitch); err != nil {
		return WriterPlan{}, err
	}
	return s.WriterPlanOf(ctx, writerID, now)
}

// WriterSubscription is one member's subscription to a writer.
type WriterSubscription struct {
	Writer    Profile   `json:"writer"`
	Tier      string    `json:"tier"`
	Provider  string    `json:"provider"`
	Renews    bool      `json:"renews"`
	ExpiresAt time.Time `json:"expires_at"`
	Active    bool      `json:"active"`
	stripeRef *string
}

const writerSubCols = `u.id::text, u.handle, u.display_name, ws.tier, ws.provider, ws.renews, ws.expires_at, ws.expires_at > $2, ws.stripe_ref`

func scanWriterSub(r pgx.Row) (WriterSubscription, error) {
	var w WriterSubscription
	err := r.Scan(&w.Writer.ID, &w.Writer.Handle, &w.Writer.DisplayName, &w.Tier, &w.Provider, &w.Renews, &w.ExpiresAt, &w.Active, &w.stripeRef)
	return w, err
}

// StripeRef is the Stripe subscription behind a web subscription, if any.
func (w WriterSubscription) StripeRef() string {
	if w.stripeRef == nil {
		return ""
	}
	return *w.stripeRef
}

// WriterSubscriptionOf returns the subscriber's subscription to a writer.
func (s *Store) WriterSubscriptionOf(ctx context.Context, subscriberID, writerID string, now time.Time) (WriterSubscription, error) {
	w, err := scanWriterSub(s.DB.QueryRow(ctx, `SELECT `+writerSubCols+` FROM writer_subscriptions ws JOIN users u ON u.id = ws.writer_id
		WHERE ws.subscriber_id::text = $1 AND ws.writer_id::text = $3`, subscriberID, now, writerID))
	return w, notFound(err)
}

// MyWriterSubscriptions lists the writers a member subscribes to, live ones first.
func (s *Store) MyWriterSubscriptions(ctx context.Context, subscriberID string, now time.Time) ([]WriterSubscription, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+writerSubCols+` FROM writer_subscriptions ws JOIN users u ON u.id = ws.writer_id
		WHERE ws.subscriber_id::text = $1 ORDER BY ws.expires_at > $2 DESC, ws.expires_at DESC LIMIT 200`, subscriberID, now)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (WriterSubscription, error) { return scanWriterSub(r) })
}

// WriterPayment is one payment for a subscription.
type WriterPayment struct {
	WriterID     string
	SubscriberID string
	Tier         string
	AmountCents  int
	Currency     string
	FeeCents     int
	AuthorCents  int
	Provider     string
	Ref          string
}

func insertWriterPayment(ctx context.Context, tx pgx.Tx, p WriterPayment, now time.Time) (bool, error) {
	tag, err := tx.Exec(ctx, `INSERT INTO writer_payments (writer_id, subscriber_id, tier, amount_cents, currency, fee_cents, author_cents, provider, provider_ref, paid_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) ON CONFLICT (provider, provider_ref) DO NOTHING`,
		p.WriterID, p.SubscriberID, p.Tier, p.AmountCents, p.Currency, p.FeeCents, p.AuthorCents, p.Provider, p.Ref, now)
	return tag.RowsAffected() == 1, err
}

// AddWriterPass records an in-app 30-day pass and extends the subscription
// by days from whichever is later, now or its current end. The same store
// transaction only counts once; isNew is false for a repeat.
func (s *Store) AddWriterPass(ctx context.Context, p WriterPayment, days int, now time.Time) (isNew bool, err error) {
	err = withTx(ctx, s.DB, func(tx pgx.Tx) error {
		if isNew, err = insertWriterPayment(ctx, tx, p, now); err != nil || !isNew {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO writer_subscriptions (subscriber_id, writer_id, tier, provider, expires_at)
			VALUES ($1, $2, $3, $4, $5::timestamptz + make_interval(days => $6))
			ON CONFLICT (subscriber_id, writer_id) DO UPDATE SET tier = EXCLUDED.tier, provider = EXCLUDED.provider,
				expires_at = greatest(writer_subscriptions.expires_at, $5::timestamptz) + make_interval(days => $6), updated_at = now()`,
			p.SubscriberID, p.WriterID, p.Tier, p.Provider, now, days)
		return err
	})
	return isNew, err
}

// StripeWriterEvent is the state of a writer subscription Stripe reported.
type StripeWriterEvent struct {
	Payment   WriterPayment // Ref is the Stripe subscription id
	Renews    bool          // active and not cancelled at the period end
	Paid      bool          // the current period is paid for
	ExpiresAt time.Time
}

// UpsertStripeWriterSub stores a Stripe writer subscription's state and, the
// first time a paid period is seen, records its payment. It reports whether a
// payment was recorded.
func (s *Store) UpsertStripeWriterSub(ctx context.Context, ev StripeWriterEvent, now time.Time) (paid bool, err error) {
	p := ev.Payment
	err = withTx(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO writer_subscriptions (subscriber_id, writer_id, tier, provider, stripe_ref, renews, expires_at)
			VALUES ($1, $2, $3, 'stripe', $4, $5, $6)
			ON CONFLICT (subscriber_id, writer_id) DO UPDATE SET tier = EXCLUDED.tier, provider = 'stripe', stripe_ref = EXCLUDED.stripe_ref,
				renews = EXCLUDED.renews, expires_at = greatest(EXCLUDED.expires_at,
					CASE WHEN writer_subscriptions.provider = 'stripe' THEN EXCLUDED.expires_at ELSE writer_subscriptions.expires_at END),
				updated_at = now()`,
			p.SubscriberID, p.WriterID, p.Tier, p.Ref, ev.Renews, ev.ExpiresAt); err != nil {
			return err
		}
		if !ev.Paid {
			return nil
		}
		pay := p
		pay.Ref = fmt.Sprintf("%s:%d", p.Ref, ev.ExpiresAt.Unix()) // one payment per period
		paid, err = insertWriterPayment(ctx, tx, pay, now)
		return err
	})
	return paid, err
}

// SetWriterSubRenews records that a web subscription will or won't renew.
func (s *Store) SetWriterSubRenews(ctx context.Context, subscriberID, writerID string, renews bool) error {
	_, err := s.DB.Exec(ctx, `UPDATE writer_subscriptions SET renews = $3, updated_at = now() WHERE subscriber_id::text = $1 AND writer_id::text = $2`,
		subscriberID, writerID, renews)
	return err
}

// LockedCards counts the writer's subscribers-only cards the viewer can't read yet.
func (s *Store) LockedCards(ctx context.Context, writerID, viewerID string) (int, error) {
	var n int
	err := s.DB.QueryRow(ctx, `SELECT count(*) FROM cards c WHERE c.author_id::text = $1 AND c.status = 'published'
		AND c.audience = 'subscribers' AND NOT `+visibleTo("$2"), writerID, nullableUser(viewerID)).Scan(&n)
	return n, err
}
