package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Notification is an inbox entry.
type Notification struct {
	ID        string     `json:"id"`
	Kind      string     `json:"kind"` // daily, reply, follow, circle, reward
	Text      string     `json:"text"`
	Actor     *Profile   `json:"actor"`
	PostID    *string    `json:"post_id"`
	CommentID *string    `json:"comment_id"`
	CircleID  *string    `json:"circle_id"`
	ReadAt    *time.Time `json:"read_at"`
	CreatedAt time.Time  `json:"created_at"`
}

// NewNotification is a notification to store.
type NewNotification struct {
	UserID    string
	Kind      string
	ActorID   string
	PostID    string
	CommentID string
	CircleID  string
	Text      string
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// AddNotification stores an inbox entry, unless the recipient blocked or muted the actor.
func (s *Store) AddNotification(ctx context.Context, n NewNotification) (bool, error) {
	tag, err := s.DB.Exec(ctx, `INSERT INTO notifications (user_id, kind, actor_id, card_id, comment_id, circle_id, text)
		SELECT $1, $2, $3::uuid, $4, $5::uuid, $6::uuid, $7
		WHERE NOT EXISTS (SELECT 1 FROM blocks WHERE user_id = $1 AND blocked_id = $3::uuid)
		  AND NOT ($2 = 'follow' AND EXISTS (SELECT 1 FROM notifications WHERE user_id = $1 AND kind = 'follow'
			AND actor_id = $3::uuid AND created_at > now() - interval '1 day'))`,
		n.UserID, n.Kind, nullable(n.ActorID), nullable(n.PostID), nullable(n.CommentID), nullable(n.CircleID), n.Text)
	return tag.RowsAffected() == 1, err
}

// Notifications lists a user's inbox, newest first, with the unread count.
func (s *Store) Notifications(ctx context.Context, userID string, limit int) ([]Notification, int, error) {
	rows, err := s.DB.Query(ctx, `SELECT n.id::text, n.kind, n.text, u.id::text, u.handle, u.display_name,
			n.card_id, n.comment_id::text, n.circle_id::text, n.read_at, n.created_at
		FROM notifications n LEFT JOIN users u ON u.id = n.actor_id
		WHERE n.user_id = $1 ORDER BY n.created_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, 0, err
	}
	list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Notification, error) {
		var n Notification
		var aid, ah, an *string
		err := r.Scan(&n.ID, &n.Kind, &n.Text, &aid, &ah, &an, &n.PostID, &n.CommentID, &n.CircleID, &n.ReadAt, &n.CreatedAt)
		if aid != nil {
			n.Actor = &Profile{ID: *aid, Handle: *ah, DisplayName: *an}
		}
		return n, err
	})
	if err != nil {
		return nil, 0, err
	}
	var unread int
	err = s.DB.QueryRow(ctx, `SELECT count(*) FROM notifications WHERE user_id = $1 AND read_at IS NULL`, userID).Scan(&unread)
	return list, unread, err
}

// MarkNotificationsRead marks the given notifications, or all when ids is empty, as read.
func (s *Store) MarkNotificationsRead(ctx context.Context, userID string, ids []string, now time.Time) error {
	_, err := s.DB.Exec(ctx, `UPDATE notifications SET read_at = $3 WHERE user_id = $1 AND read_at IS NULL
		AND (cardinality($2::text[]) = 0 OR id::text = ANY($2))`, userID, ids, now)
	return err
}

// RegisterDevice stores a push token for the user (moving it if another account had it).
func (s *Store) RegisterDevice(ctx context.Context, userID, platform, token string) error {
	_, err := s.DB.Exec(ctx, `INSERT INTO devices (token, user_id, platform) VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = now()`,
		token, userID, platform)
	return err
}

// RemoveDevice forgets a push token. userID "" removes it whoever owns it.
func (s *Store) RemoveDevice(ctx context.Context, userID, token string) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM devices WHERE token = $1 AND ($2 = '' OR user_id::text = $2)`, token, userID)
	return err
}

// DeviceTokens returns a user's push tokens if they allow notifications of this setting.
func (s *Store) DeviceTokens(ctx context.Context, userID, setting string) ([]string, error) {
	rows, err := s.DB.Query(ctx, `SELECT d.token FROM devices d JOIN users u ON u.id = d.user_id
		WHERE d.user_id = $1 AND coalesce((u.notify ->> $2)::boolean, true)`, userID, setting)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

// DailyRecipient is a user due their daily idea push.
type DailyRecipient struct {
	UserID string
	Topics []string
	Day    string // the user's local date
}

// DueDailyPushes returns users for whom it is now 8am or later local time,
// who haven't had today's daily idea, have a device and allow it. It claims
// them, so a second server running the same job skips them.
func (s *Store) DueDailyPushes(ctx context.Context, now time.Time, limit int) ([]DailyRecipient, error) {
	rows, err := s.DB.Query(ctx, `WITH due AS (
			SELECT u.id, (($1::timestamptz AT TIME ZONE u.timezone))::date AS day
			FROM users u
			WHERE coalesce((u.notify ->> 'daily')::boolean, true)
			  AND extract(hour FROM ($1::timestamptz AT TIME ZONE u.timezone)) >= 8
			  AND (u.last_daily_push IS NULL OR u.last_daily_push < (($1::timestamptz AT TIME ZONE u.timezone))::date)
			  AND EXISTS (SELECT 1 FROM devices d WHERE d.user_id = u.id)
			ORDER BY u.id LIMIT $2 FOR UPDATE SKIP LOCKED
		)
		UPDATE users u SET last_daily_push = due.day FROM due WHERE u.id = due.id
		RETURNING u.id::text, u.topics, to_char(due.day, 'YYYY-MM-DD')`, now, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (DailyRecipient, error) {
		var d DailyRecipient
		err := r.Scan(&d.UserID, &d.Topics, &d.Day)
		return d, err
	})
}
