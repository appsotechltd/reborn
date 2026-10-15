package store

import (
	"context"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/srs"
	"github.com/jackc/pgx/v5"
)

// ReviewItem is a card due for review.
type ReviewItem struct {
	Card         Card      `json:"card"`
	DueAt        time.Time `json:"due_at"`
	Reps         int       `json:"reps"`
	IntervalDays int       `json:"interval_days"`
}

// DueReviews returns the user's cards due at now, oldest first, and the total due.
func (s *Store) DueReviews(ctx context.Context, userID string, now time.Time, limit int) ([]ReviewItem, int, error) {
	var total int
	if err := s.DB.QueryRow(ctx, `SELECT count(*) FROM reviews r JOIN cards c ON c.id = r.card_id
		WHERE r.user_id = $1 AND r.due_at <= $2 AND c.status = 'published'`, userID, now).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+`, r.due_at, r.reps, r.interval_days`+cardFrom+`
		JOIN reviews r ON r.card_id = c.id
		WHERE r.user_id = $1 AND r.due_at <= $2 AND c.status = 'published'
		ORDER BY r.due_at, c.id LIMIT $3`, userID, now, limit)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []ReviewItem{}
	for rows.Next() {
		var it ReviewItem
		var extra struct {
			due      time.Time
			reps, iv int
		}
		c, err := scanCardWith(rows, &extra.due, &extra.reps, &extra.iv)
		if err != nil {
			return nil, 0, err
		}
		it.Card, it.DueAt, it.Reps, it.IntervalDays = c, extra.due, extra.reps, extra.iv
		items = append(items, it)
	}
	return items, total, rows.Err()
}

// Grade records a review and returns the new schedule. A card that was never
// enrolled is enrolled on its first grade.
func (s *Store) Grade(ctx context.Context, userID, cardID string, g srs.Grade, now time.Time) (srs.State, error) {
	var next srs.State
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var exists bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM cards WHERE id = $1 AND status = 'published')`, cardID).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return ErrNotFound
		}
		var cur srs.State
		var ease float32
		err := tx.QueryRow(ctx, `SELECT ease, interval_days, reps, lapses, due_at FROM reviews
			WHERE user_id = $1 AND card_id = $2 FOR UPDATE`, userID, cardID).Scan(&ease, &cur.IntervalDays, &cur.Reps, &cur.Lapses, &cur.DueAt)
		if err == pgx.ErrNoRows {
			cur = srs.New(now)
		} else if err != nil {
			return err
		} else {
			cur.Ease = float64(ease)
		}
		next = srs.Next(cur, g, now)
		_, err = tx.Exec(ctx, `INSERT INTO reviews (user_id, card_id, ease, interval_days, reps, lapses, due_at, last_reviewed_at)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
			ON CONFLICT (user_id, card_id) DO UPDATE SET ease=EXCLUDED.ease, interval_days=EXCLUDED.interval_days,
				reps=EXCLUDED.reps, lapses=EXCLUDED.lapses, due_at=EXCLUDED.due_at, last_reviewed_at=EXCLUDED.last_reviewed_at`,
			userID, cardID, next.Ease, next.IntervalDays, next.Reps, next.Lapses, next.DueAt, now)
		return err
	})
	return next, err
}

// QuizCards returns cards that have a quiz, preferring the user's stashed and
// reviewed cards, then anything else in the topic.
func (s *Store) QuizCards(ctx context.Context, userID, topic string, limit int) ([]Card, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`
		WHERE c.status = 'published' AND c.quiz IS NOT NULL AND ($2 = '' OR c.topic = $2)
		ORDER BY EXISTS (SELECT 1 FROM reviews r WHERE r.user_id = $1 AND r.card_id = c.id) DESC, random()
		LIMIT $3`, userID, topic, limit)
	if err != nil {
		return nil, err
	}
	return collectCards(rows)
}

// scanCardWith scans a card row followed by extra columns.
func scanCardWith(row pgx.Row, extra ...any) (Card, error) {
	var holder Card
	var quiz []byte
	var m memberScan
	dest := []any{&holder.ID, &holder.Title, &holder.Body, &holder.Quote, &holder.ApplyIt, &holder.Topic, &holder.Tags, &holder.Locator, &holder.Health, &quiz,
		&holder.Source.ID, &holder.Source.Title, &holder.Source.Authors, &holder.Source.Kind, &holder.Source.URL, &holder.Source.Licence, &holder.Source.LicenceURL, &holder.Source.Attribution,
		&m.authorID, &m.handle, &m.name, &m.categoryID, &m.categoryName, &m.media, &m.status, &m.audience, &m.createdAt}
	if err := row.Scan(append(dest, extra...)...); err != nil {
		return holder, err
	}
	if m.authorID != nil {
		holder.member = &m
	}
	return finishCard(holder, quiz)
}
