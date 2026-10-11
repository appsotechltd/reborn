package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Subscription is a store subscription to premium.
type Subscription struct {
	UserID    string
	Provider  string
	Ref       string // Stripe subscription id, Apple original transaction id, Google purchase token
	Plan      string // monthly or yearly
	Status    string // active, canceled, revoked, …
	ExpiresAt time.Time
}

// UpsertSubscription records a subscription's latest state.
func (s *Store) UpsertSubscription(ctx context.Context, sub Subscription) error {
	_, err := s.DB.Exec(ctx, `INSERT INTO subscriptions (user_id, provider, provider_ref, plan, status, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (provider, provider_ref) DO UPDATE SET plan = EXCLUDED.plan, status = EXCLUDED.status,
			expires_at = EXCLUDED.expires_at, updated_at = now()`,
		sub.UserID, sub.Provider, sub.Ref, sub.Plan, sub.Status, sub.ExpiresAt)
	return err
}

// SubscriptionUser finds who owns a store subscription.
func (s *Store) SubscriptionUser(ctx context.Context, provider, ref string) (string, error) {
	var id string
	err := s.DB.QueryRow(ctx, `SELECT user_id::text FROM subscriptions WHERE provider = $1 AND provider_ref = $2`, provider, ref).Scan(&id)
	return id, notFound(err)
}

// ActiveSubscription returns the user's subscription that runs longest, if any is current.
func (s *Store) ActiveSubscription(ctx context.Context, userID string, now time.Time) (*Subscription, error) {
	var sub Subscription
	err := s.DB.QueryRow(ctx, `SELECT user_id::text, provider, provider_ref, plan, status, expires_at FROM subscriptions
		WHERE user_id = $1 AND status <> 'revoked' AND expires_at > $2 ORDER BY expires_at DESC LIMIT 1`, userID, now).
		Scan(&sub.UserID, &sub.Provider, &sub.Ref, &sub.Plan, &sub.Status, &sub.ExpiresAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	return &sub, err
}

// GrantPremium adds free premium days, starting when the user's current premium ends.
func (s *Store) GrantPremium(ctx context.Context, userID, reason string, days int, now time.Time) error {
	_, err := s.DB.Exec(ctx, `INSERT INTO premium_grants (user_id, reason, starts_at, expires_at)
		SELECT users.id, $2, greatest($4, coalesce(`+premiumUntil+`, $4)), greatest($4, coalesce(`+premiumUntil+`, $4)) + make_interval(days => $3)
		FROM users WHERE users.id = $1`, userID, reason, days, now)
	return err
}

// SetStripeCustomer remembers a user's Stripe customer id.
func (s *Store) SetStripeCustomer(ctx context.Context, userID, customerID string) error {
	_, err := s.DB.Exec(ctx, `UPDATE users SET stripe_customer_id = $2 WHERE id::text = $1`, userID, customerID)
	return err
}

// StripeCustomer returns the user's Stripe customer id, or "".
func (s *Store) StripeCustomer(ctx context.Context, userID string) (string, error) {
	var id *string
	if err := s.DB.QueryRow(ctx, `SELECT stripe_customer_id FROM users WHERE id = $1`, userID).Scan(&id); err != nil {
		return "", notFound(err)
	}
	if id == nil {
		return "", ErrNotFound
	}
	return *id, nil
}

// ReferralRewardDays is the premium both people get when a referral sticks.
const ReferralRewardDays = 7

// ReferralRewardsPerYear caps how many referral rewards one person can earn.
const ReferralRewardsPerYear = 12

// ClaimReferralReward marks a referred user's reward as given and returns the
// referrer, or "" when there is nothing to give. Both get ReferralRewardDays of premium.
func (s *Store) ClaimReferralReward(ctx context.Context, userID string, now time.Time) (string, error) {
	var referrer *string
	err := s.DB.QueryRow(ctx, `UPDATE users SET referral_rewarded_at = $2
		WHERE id = $1 AND referred_by IS NOT NULL AND referral_rewarded_at IS NULL RETURNING referred_by::text`, userID, now).Scan(&referrer)
	if err == pgx.ErrNoRows || referrer == nil {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if err := s.GrantPremium(ctx, userID, "referred", ReferralRewardDays, now); err != nil {
		return "", err
	}
	var earned int
	if err := s.DB.QueryRow(ctx, `SELECT count(*) FROM premium_grants WHERE user_id::text = $1 AND reason = 'referral'
		AND created_at > $2::timestamptz - interval '365 days'`, *referrer, now).Scan(&earned); err != nil {
		return "", err
	}
	if earned >= ReferralRewardsPerYear {
		return "", nil
	}
	return *referrer, s.GrantPremium(ctx, *referrer, "referral", ReferralRewardDays, now)
}

// ReferralStats is how a user's invites are doing.
type ReferralStats struct {
	Code     string `json:"code"`
	Invited  int    `json:"invited"`
	Rewarded int    `json:"rewarded"`
}

// Referrals returns the user's referral code and counts.
func (s *Store) Referrals(ctx context.Context, userID string) (ReferralStats, error) {
	var r ReferralStats
	err := s.DB.QueryRow(ctx, `SELECT u.referral_code,
			(SELECT count(*) FROM users x WHERE x.referred_by = u.id),
			(SELECT count(*) FROM users x WHERE x.referred_by = u.id AND x.referral_rewarded_at IS NOT NULL)
		FROM users u WHERE u.id = $1`, userID).Scan(&r.Code, &r.Invited, &r.Rewarded)
	return r, notFound(err)
}
