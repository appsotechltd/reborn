package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Stats is the moderator dashboard.
type Stats struct {
	Users struct {
		Total   int `json:"total"`
		New7d   int `json:"new_7d"`
		New30d  int `json:"new_30d"`
		DAU     int `json:"dau"`
		WAU     int `json:"wau"`
		MAU     int `json:"mau"`
		Premium int `json:"premium"`
	} `json:"users"`
	// Retention is the share of people who signed up 8-37 days ago and came
	// back 1 day and 7 days after signing up.
	Retention struct {
		Cohort int     `json:"cohort"`
		D1     float64 `json:"d1"`
		D7     float64 `json:"d7"`
	} `json:"retention"`
	Engagement struct {
		IdeasRead7d int `json:"ideas_read_7d"`
		Reactions7d int `json:"reactions_7d"`
		Comments7d  int `json:"comments_7d"`
		Favorites7d int `json:"favorites_7d"`
		Shares7d    int `json:"shares_7d"`
	} `json:"engagement"`
	Revenue struct {
		Gifts30d      []ProviderAmount `json:"gifts_30d"`
		Subscriptions []ProviderCount  `json:"subscriptions"` // active, by provider
	} `json:"revenue"`
	Moderation struct {
		PendingContributions int `json:"pending_contributions"`
		ReportedComments     int `json:"reported_comments"`
	} `json:"moderation"`
	Content struct {
		Posts   int `json:"posts"`
		Sources int `json:"sources"`
	} `json:"content"`
	Daily    []DailyStat `json:"daily"` // last 30 days, oldest first
	TopPosts []TopPost   `json:"top_posts"`
}

// ProviderAmount is gift revenue for one provider.
type ProviderAmount struct {
	Provider    string `json:"provider"`
	Currency    string `json:"currency"`
	AmountCents int    `json:"amount_cents"`
	Count       int    `json:"count"`
}

// ProviderCount counts active subscriptions for one provider.
type ProviderCount struct {
	Provider string `json:"provider"`
	Count    int    `json:"count"`
}

// DailyStat is one day of signups and active users (UTC).
type DailyStat struct {
	Day     string `json:"day"`
	Signups int    `json:"signups"`
	Active  int    `json:"active"`
}

// TopPost is a post with its activity this week.
type TopPost struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Score int    `json:"score"`
}

// AdminStats gathers the dashboard numbers as of now.
func (s *Store) AdminStats(ctx context.Context, now time.Time) (Stats, error) {
	var st Stats
	d7, d30 := now.AddDate(0, 0, -7), now.AddDate(0, 0, -30)
	err := s.DB.QueryRow(ctx, `SELECT
			(SELECT count(*) FROM users),
			(SELECT count(*) FROM users WHERE created_at >= $2),
			(SELECT count(*) FROM users WHERE created_at >= $3),
			(SELECT count(DISTINCT user_id) FROM activity_days WHERE day >= ($1::timestamptz)::date - 1),
			(SELECT count(DISTINCT user_id) FROM activity_days WHERE day >= ($2::timestamptz)::date),
			(SELECT count(DISTINCT user_id) FROM activity_days WHERE day >= ($3::timestamptz)::date),
			(SELECT count(*) FROM users WHERE `+premiumUntil+` > $1),
			(SELECT coalesce(sum(ideas), 0) FROM activity_days WHERE day >= ($2::timestamptz)::date),
			(SELECT count(*) FROM reactions WHERE created_at >= $2),
			(SELECT count(*) FROM comments WHERE created_at >= $2),
			(SELECT count(*) FROM favorites WHERE created_at >= $2),
			(SELECT count(*) FROM shares WHERE created_at >= $2),
			(SELECT count(*) FROM contributions WHERE status = 'pending'),
			(SELECT count(DISTINCT comment_id) FROM comment_reports),
			(SELECT count(*) FROM cards WHERE status = 'published'),
			(SELECT count(DISTINCT source_id) FROM cards WHERE status = 'published')`, now, d7, d30).Scan(
		&st.Users.Total, &st.Users.New7d, &st.Users.New30d, &st.Users.DAU, &st.Users.WAU, &st.Users.MAU, &st.Users.Premium,
		&st.Engagement.IdeasRead7d, &st.Engagement.Reactions7d, &st.Engagement.Comments7d, &st.Engagement.Favorites7d, &st.Engagement.Shares7d,
		&st.Moderation.PendingContributions, &st.Moderation.ReportedComments, &st.Content.Posts, &st.Content.Sources)
	if err != nil {
		return st, err
	}
	var d1, d7n int
	if err := s.DB.QueryRow(ctx, `WITH cohort AS (
			SELECT id, (created_at AT TIME ZONE timezone)::date AS d0 FROM users
			WHERE created_at < $1::timestamptz - interval '8 days' AND created_at >= $1::timestamptz - interval '37 days'
		) SELECT count(*),
			count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity_days a WHERE a.user_id = cohort.id AND a.day = cohort.d0 + 1)),
			count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity_days a WHERE a.user_id = cohort.id AND a.day = cohort.d0 + 7))
		FROM cohort`, now).Scan(&st.Retention.Cohort, &d1, &d7n); err != nil {
		return st, err
	}
	if st.Retention.Cohort > 0 {
		st.Retention.D1 = float64(d1) / float64(st.Retention.Cohort)
		st.Retention.D7 = float64(d7n) / float64(st.Retention.Cohort)
	}
	rows, err := s.DB.Query(ctx, `SELECT provider, currency, sum(amount_cents)::int, count(*) FROM gifts
		WHERE status = 'paid' AND paid_at >= $1 GROUP BY provider, currency ORDER BY provider`, d30)
	if err != nil {
		return st, err
	}
	if st.Revenue.Gifts30d, err = pgx.CollectRows(rows, pgx.RowToStructByPos[ProviderAmount]); err != nil {
		return st, err
	}
	rows, err = s.DB.Query(ctx, `SELECT provider, count(DISTINCT user_id)::int FROM subscriptions
		WHERE status <> 'revoked' AND expires_at > $1 GROUP BY provider ORDER BY provider`, now)
	if err != nil {
		return st, err
	}
	if st.Revenue.Subscriptions, err = pgx.CollectRows(rows, pgx.RowToStructByPos[ProviderCount]); err != nil {
		return st, err
	}
	rows, err = s.DB.Query(ctx, `SELECT to_char(d, 'YYYY-MM-DD'),
			(SELECT count(*) FROM users WHERE (created_at AT TIME ZONE 'UTC')::date = d)::int,
			(SELECT count(DISTINCT user_id) FROM activity_days WHERE day = d)::int
		FROM generate_series(($1::timestamptz AT TIME ZONE 'UTC')::date - 29, ($1::timestamptz AT TIME ZONE 'UTC')::date, interval '1 day') AS g(d)
		ORDER BY d`, now)
	if err != nil {
		return st, err
	}
	if st.Daily, err = pgx.CollectRows(rows, pgx.RowToStructByPos[DailyStat]); err != nil {
		return st, err
	}
	rows, err = s.DB.Query(ctx, `SELECT c.id, c.title, `+trendScore+`::int FROM cards c
		WHERE c.status = 'published' AND `+trendScore+` > 0 ORDER BY 3 DESC, c.id LIMIT 10`, d7)
	if err != nil {
		return st, err
	}
	st.TopPosts, err = pgx.CollectRows(rows, pgx.RowToStructByPos[TopPost])
	return st, err
}
