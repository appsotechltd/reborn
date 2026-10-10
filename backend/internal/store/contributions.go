package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/jackc/pgx/v5"
)

// ContributionSource is the source a contributor names.
type ContributionSource struct {
	Title   string   `json:"title"`
	Authors []string `json:"authors"`
	URL     string   `json:"url"`
	Kind    string   `json:"kind"`
}

// Contribution is a user-submitted idea awaiting or past moderation.
type Contribution struct {
	ID            string             `json:"id"`
	Status        string             `json:"status"`
	Source        ContributionSource `json:"source"`
	Topic         string             `json:"topic"`
	Title         string             `json:"title"`
	Body          string             `json:"body"`
	ApplyIt       string             `json:"apply_it"`
	Tags          []string           `json:"tags"`
	Quiz          *content.Quiz      `json:"quiz"`
	ModeratorNote *string            `json:"moderator_note"`
	CardID        *string            `json:"card_id"`
	CreatedAt     time.Time          `json:"created_at"`
	UserID        string             `json:"-"`
}

const contribCols = `id::text, status, source, topic, title, body, apply_it, tags, quiz, moderator_note, card_id, created_at, user_id::text`

func scanContribution(row pgx.Row) (Contribution, error) {
	var c Contribution
	var src, quiz []byte
	err := row.Scan(&c.ID, &c.Status, &src, &c.Topic, &c.Title, &c.Body, &c.ApplyIt, &c.Tags, &quiz, &c.ModeratorNote, &c.CardID, &c.CreatedAt, &c.UserID)
	if err != nil {
		return c, err
	}
	if err := json.Unmarshal(src, &c.Source); err != nil {
		return c, err
	}
	if len(quiz) > 0 {
		c.Quiz = &content.Quiz{}
		if err := json.Unmarshal(quiz, c.Quiz); err != nil {
			return c, err
		}
	}
	if c.Tags == nil {
		c.Tags = []string{}
	}
	return c, nil
}

func collectContributions(rows pgx.Rows) ([]Contribution, error) {
	defer rows.Close()
	out := []Contribution{}
	for rows.Next() {
		c, err := scanContribution(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// CreateContribution stores a pending contribution.
func (s *Store) CreateContribution(ctx context.Context, userID string, c Contribution) (Contribution, error) {
	src, err := json.Marshal(c.Source)
	if err != nil {
		return c, err
	}
	var quiz []byte
	if c.Quiz != nil {
		if quiz, err = json.Marshal(c.Quiz); err != nil {
			return c, err
		}
	}
	tags := c.Tags
	if tags == nil {
		tags = []string{}
	}
	return scanContribution(s.DB.QueryRow(ctx, `INSERT INTO contributions (user_id, source, topic, title, body, apply_it, tags, quiz)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING `+contribCols, userID, src, c.Topic, c.Title, c.Body, c.ApplyIt, tags, quiz))
}

// MyContributions lists a user's contributions, newest first.
func (s *Store) MyContributions(ctx context.Context, userID string) ([]Contribution, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+contribCols+` FROM contributions WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	return collectContributions(rows)
}

// PendingContributions lists the moderation queue, oldest first.
func (s *Store) PendingContributions(ctx context.Context) ([]Contribution, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+contribCols+` FROM contributions WHERE status = 'pending' ORDER BY created_at`)
	if err != nil {
		return nil, err
	}
	return collectContributions(rows)
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

// Slugify turns a title into a source-id-safe slug of at most max chars.
func Slugify(s string, max int) string {
	slug := strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(s), "-"), "-")
	if len(slug) > max {
		slug = strings.Trim(slug[:max], "-")
	}
	if slug == "" {
		slug = "source"
	}
	return slug
}

// ContributionSourceID derives a stable source id from the contributed URL,
// so two people contributing ideas from the same source share one page.
func ContributionSourceID(src ContributionSource) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(src.URL))))
	return Slugify(src.Title, 60) + "-" + hex.EncodeToString(sum[:])[:8]
}

// ApproveContribution publishes a pending contribution as a card. Contributed
// cards are the contributor's own words, so their source is licensed
// original-summary and credits the contributor's named source with a link.
func (s *Store) ApproveContribution(ctx context.Context, id, moderatorID, note string, now time.Time) (Contribution, error) {
	var out Contribution
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		c, err := scanContribution(tx.QueryRow(ctx, `SELECT `+contribCols+` FROM contributions WHERE id::text = $1 FOR UPDATE`, id))
		if err != nil {
			return notFound(err)
		}
		if c.Status != "pending" {
			return ErrConflict
		}
		src := content.Source{
			ID:          ContributionSourceID(c.Source),
			Title:       c.Source.Title,
			Authors:     c.Source.Authors,
			Kind:        c.Source.Kind,
			URL:         c.Source.URL,
			Licence:     "original-summary",
			LicenceURL:  c.Source.URL,
			Attribution: fmt.Sprintf("%s, %s (community summary)", strings.Join(c.Source.Authors, ", "), c.Source.Title),
			RetrievedAt: now.Format("2006-01-02"),
		}
		// Serialise approvals per source so card numbers never collide.
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, src.ID); err != nil {
			return err
		}
		var existing bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM sources WHERE id = $1)`, src.ID).Scan(&existing); err != nil {
			return err
		}
		if !existing {
			if err := upsertSource(ctx, tx, src); err != nil {
				return err
			}
		} else if err := tx.QueryRow(ctx, `SELECT attribution, language FROM sources WHERE id = $1`, src.ID).Scan(&src.Attribution, &src.Language); err != nil {
			return err
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM cards WHERE source_id = $1`, src.ID).Scan(&n); err != nil {
			return err
		}
		card := content.Card{
			ID: fmt.Sprintf("%s--%02d", src.ID, n+1), Topic: c.Topic, Tags: c.Tags, Title: c.Title, Body: c.Body,
			ApplyIt: c.ApplyIt, Quiz: c.Quiz, Health: c.Topic == "health",
		}
		if _, err := upsertCard(ctx, tx, src, card, c.UserID); err != nil {
			return err
		}
		out, err = scanContribution(tx.QueryRow(ctx, `UPDATE contributions SET status = 'approved', moderator_id = $2,
			moderator_note = NULLIF($3, ''), card_id = $4, decided_at = $5 WHERE id::text = $1 RETURNING `+contribCols,
			id, moderatorID, note, card.ID, now))
		return err
	})
	return out, err
}

// RejectContribution closes a pending contribution with a note.
func (s *Store) RejectContribution(ctx context.Context, id, moderatorID, note string, now time.Time) (Contribution, error) {
	c, err := scanContribution(s.DB.QueryRow(ctx, `UPDATE contributions SET status = 'rejected', moderator_id = $2,
		moderator_note = $3, decided_at = $4 WHERE id::text = $1 AND status = 'pending' RETURNING `+contribCols, id, moderatorID, note, now))
	if err == pgx.ErrNoRows {
		var exists bool
		if e := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM contributions WHERE id::text = $1)`, id).Scan(&exists); e == nil && exists {
			return c, ErrConflict
		}
		return c, ErrNotFound
	}
	return c, err
}
