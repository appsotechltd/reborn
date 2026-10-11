package store

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// User is the API shape of an account.
type User struct {
	ID           string          `json:"id"`
	Email        string          `json:"email"`
	Handle       string          `json:"handle"`
	DisplayName  string          `json:"display_name"`
	Bio          string          `json:"bio"`
	Role         string          `json:"role"`
	Topics       []string        `json:"topics"`
	Timezone     string          `json:"timezone"`
	DailyGoal    int             `json:"daily_goal"`
	Notify       map[string]bool `json:"notify"`
	ReferralCode string          `json:"referral_code"`
	Premium      bool            `json:"premium"`
	PremiumUntil *time.Time      `json:"premium_until"`
}

// NotifyKinds are the notification settings a user can switch off.
var NotifyKinds = []string{"daily", "replies", "follows", "circles"}

// premiumUntil is the latest end of a subscription or free grant.
const premiumUntil = `(SELECT max(e) FROM (
		SELECT expires_at AS e FROM subscriptions WHERE user_id = users.id AND status <> 'revoked'
		UNION ALL SELECT expires_at FROM premium_grants WHERE user_id = users.id) AS p)`

const userCols = `id::text, email, handle, display_name, bio, role, topics, timezone, daily_goal, notify, referral_code, ` +
	premiumUntil + `, coalesce(` + premiumUntil + ` > now(), false)`

func scanUser(row pgx.Row, extra ...any) (User, error) {
	var u User
	err := row.Scan(append([]any{&u.ID, &u.Email, &u.Handle, &u.DisplayName, &u.Bio, &u.Role, &u.Topics,
		&u.Timezone, &u.DailyGoal, &u.Notify, &u.ReferralCode, &u.PremiumUntil, &u.Premium}, extra...)...)
	return u, err
}

func newReferralCode() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 8)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		b[i] = alphabet[n.Int64()]
	}
	return string(b)
}

// HandleRE is what a handle may look like.
var HandleRE = regexp.MustCompile(`^[a-z0-9_]{3,30}$`)

// ErrHandleTaken is returned when another account has the handle.
var ErrHandleTaken = errors.New("handle taken")

// baseHandle turns a display name or email into a handle candidate.
func baseHandle(name string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(name) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '_':
			b.WriteRune(r)
		case r == ' ' || r == '.' || r == '-':
			b.WriteRune('_')
		}
	}
	h := strings.Trim(b.String(), "_")
	if len(h) > 20 {
		h = h[:20]
	}
	if len(h) < 3 {
		h = "reader" + h
	}
	return h
}

func randomSuffix() string {
	v, _ := rand.Int(rand.Reader, big.NewInt(10000))
	return fmt.Sprintf("%04d", v.Int64())
}

func isUnique(err error, constraint string) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505" && (constraint == "" || pgErr.ConstraintName == constraint)
}

// CreateUser inserts a user with a handle derived from their name; ErrConflict
// means the email is taken. referrerID may be "".
func (s *Store) CreateUser(ctx context.Context, email, hash, name, referrerID string) (User, error) {
	var ref any
	if referrerID != "" {
		ref = referrerID
	}
	base := baseHandle(name)
	for attempt := range 8 {
		handle := base
		if attempt > 0 {
			handle = base + randomSuffix()
		}
		u, err := scanUser(s.DB.QueryRow(ctx, `INSERT INTO users (email, password_hash, display_name, handle, referral_code, referred_by)
			VALUES ($1, $2, $3, $4, $5, $6) RETURNING `+userCols,
			strings.ToLower(strings.TrimSpace(email)), hash, name, handle, newReferralCode(), ref))
		if isUnique(err, "users_handle_idx") || isUnique(err, "users_referral_code_idx") {
			continue
		}
		if isUnique(err, "") {
			return u, ErrConflict
		}
		return u, err
	}
	return User{}, ErrConflict
}

// UserIDByReferralCode finds the user a referral code belongs to.
func (s *Store) UserIDByReferralCode(ctx context.Context, code string) (string, error) {
	var id string
	err := s.DB.QueryRow(ctx, `SELECT id::text FROM users WHERE referral_code = upper($1)`, strings.TrimSpace(code)).Scan(&id)
	return id, notFound(err)
}

// UserByEmail returns a user and their password hash.
func (s *Store) UserByEmail(ctx context.Context, email string) (User, string, error) {
	var hash string
	u, err := scanUser(s.DB.QueryRow(ctx, `SELECT `+userCols+`, password_hash FROM users WHERE email = $1`,
		strings.ToLower(strings.TrimSpace(email))), &hash)
	return u, hash, notFound(err)
}

// UserByID returns a user.
func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	u, err := scanUser(s.DB.QueryRow(ctx, `SELECT `+userCols+` FROM users WHERE id = $1`, id))
	return u, notFound(err)
}

// UserUpdate holds the profile fields to change; nil leaves a field as is.
type UserUpdate struct {
	DisplayName *string
	Handle      *string
	Bio         *string
	Topics      []string
	Timezone    *string
	DailyGoal   *int
	Notify      map[string]bool // merged into the current settings
}

// UpdateUser changes profile fields. ErrHandleTaken means the handle is in use.
func (s *Store) UpdateUser(ctx context.Context, id string, in UserUpdate) (User, error) {
	notify := in.Notify
	if notify == nil {
		notify = map[string]bool{}
	}
	u, err := scanUser(s.DB.QueryRow(ctx, `UPDATE users SET display_name = coalesce($2, display_name),
		topics = coalesce($3, topics), handle = coalesce($4, handle), bio = coalesce($5, bio),
		timezone = coalesce($6, timezone), daily_goal = coalesce($7, daily_goal), notify = notify || $8::jsonb
		WHERE id = $1 RETURNING `+userCols, id, in.DisplayName, in.Topics, in.Handle, in.Bio, in.Timezone, in.DailyGoal, notify))
	if isUnique(err, "users_handle_idx") {
		return u, ErrHandleTaken
	}
	return u, notFound(err)
}

// DeleteUser removes an account and everything that belongs to it. Approved
// contributions stay published without a name on them.
func (s *Store) DeleteUser(ctx context.Context, id string) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// CreatePasswordReset stores a reset token's hash for the user with email.
// It returns ErrNotFound when there is no such account.
func (s *Store) CreatePasswordReset(ctx context.Context, email, tokenHash string, expires time.Time) (User, error) {
	u, _, err := s.UserByEmail(ctx, email)
	if err != nil {
		return u, err
	}
	_, err = s.DB.Exec(ctx, `INSERT INTO password_resets (token_hash, user_id, expires_at) VALUES ($1, $2, $3)`, tokenHash, u.ID, expires)
	return u, err
}

// ResetPassword sets a new password hash if the token is unused and unexpired,
// and spends every outstanding token for that user.
func (s *Store) ResetPassword(ctx context.Context, tokenHash, passwordHash string, now time.Time) (User, error) {
	var u User
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var uid string
		err := tx.QueryRow(ctx, `SELECT user_id::text FROM password_resets
			WHERE token_hash = $1 AND used_at IS NULL AND expires_at > $2 FOR UPDATE`, tokenHash, now).Scan(&uid)
		if err != nil {
			return notFound(err)
		}
		if _, err := tx.Exec(ctx, `UPDATE password_resets SET used_at = $2 WHERE user_id = $1 AND used_at IS NULL`, uid, now); err != nil {
			return err
		}
		u, err = scanUser(tx.QueryRow(ctx, `UPDATE users SET password_hash = $2 WHERE id = $1 RETURNING `+userCols, uid, passwordHash))
		return err
	})
	return u, err
}

// SetRole changes a user's role by email.
func (s *Store) SetRole(ctx context.Context, email, role string) error {
	tag, err := s.DB.Exec(ctx, `UPDATE users SET role = $2 WHERE email = $1`, strings.ToLower(strings.TrimSpace(email)), role)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
