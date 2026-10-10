package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/jackc/pgx/v5"
)

// SourceRef is the source summary embedded in every card.
type SourceRef struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Authors     []string `json:"authors"`
	Kind        string   `json:"kind"`
	URL         string   `json:"url"`
	Licence     string   `json:"licence"`
	LicenceURL  string   `json:"licence_url"`
	Attribution string   `json:"attribution"`
}

// Card is the API shape of an idea card.
type Card struct {
	ID         string        `json:"id"`
	Title      string        `json:"title"`
	Body       string        `json:"body"`
	Quote      *string       `json:"quote,omitempty"`
	ApplyIt    string        `json:"apply_it"`
	Topic      string        `json:"topic"`
	Tags       []string      `json:"tags"`
	Locator    *string       `json:"locator,omitempty"`
	Health     bool          `json:"health"`
	Disclaimer *string       `json:"disclaimer"`
	Quiz       *content.Quiz `json:"quiz,omitempty"`
	Source     SourceRef     `json:"source"`
	Credit     string        `json:"credit"`
}

// cardCols selects a card joined with its source; scanCard reads it.
const cardCols = `c.id, c.title, c.body, c.quote, c.apply_it, c.topic, c.tags, c.locator, c.health, c.quiz,
	s.id, s.title, s.authors, s.kind, s.url, s.licence, s.licence_url, s.attribution`

const cardFrom = ` FROM cards c JOIN sources s ON s.id = c.source_id `

func scanCard(row pgx.Row) (Card, error) { return scanCardWith(row) }

func finishCard(c Card, quiz []byte) (Card, error) {
	if len(quiz) > 0 {
		c.Quiz = &content.Quiz{}
		if err := json.Unmarshal(quiz, c.Quiz); err != nil {
			return c, err
		}
	}
	if c.Tags == nil {
		c.Tags = []string{}
	}
	if c.Health {
		d := content.HealthDisclaimer
		c.Disclaimer = &d
	}
	c.Credit = "Source: " + c.Source.Attribution
	return c, nil
}

func collectCards(rows pgx.Rows) ([]Card, error) {
	defer rows.Close()
	out := []Card{}
	for rows.Next() {
		c, err := scanCard(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// GetCard returns a published card.
func (s *Store) GetCard(ctx context.Context, id string) (Card, error) {
	c, err := scanCard(s.DB.QueryRow(ctx, `SELECT `+cardCols+cardFrom+`WHERE c.id = $1 AND c.status = 'published'`, id))
	return c, notFound(err)
}

// GetCards returns published cards by id, in the order given.
func (s *Store) GetCards(ctx context.Context, ids []string) ([]Card, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`
		JOIN unnest($1::text[]) WITH ORDINALITY AS o(id, n) ON o.id = c.id
		WHERE c.status = 'published' ORDER BY o.n`, ids)
	if err != nil {
		return nil, err
	}
	return collectCards(rows)
}

// SourceCards returns a source and its published cards.
func (s *Store) SourceCards(ctx context.Context, id string) (content.Source, []Card, error) {
	var src content.Source
	err := s.DB.QueryRow(ctx, `SELECT id, title, authors, kind, url, licence, licence_url, attribution,
		coalesce(publisher,''), year, language, coalesce(translator,''), to_char(retrieved_at, 'YYYY-MM-DD'), coalesce(notes,'')
		FROM sources WHERE id = $1`, id).Scan(&src.ID, &src.Title, &src.Authors, &src.Kind, &src.URL, &src.Licence,
		&src.LicenceURL, &src.Attribution, &src.Publisher, &src.Year, &src.Language, &src.Translator, &src.RetrievedAt, &src.Notes)
	if err != nil {
		return src, nil, notFound(err)
	}
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`WHERE c.source_id = $1 AND c.status = 'published' ORDER BY c.id`, id)
	if err != nil {
		return src, nil, err
	}
	cards, err := collectCards(rows)
	return src, cards, err
}

// TopicCount is a topic with its number of published cards.
type TopicCount struct {
	Slug      string `json:"slug"`
	Name      string `json:"name"`
	CardCount int    `json:"card_count"`
}

// Topics lists topics in display order with card counts.
func (s *Store) Topics(ctx context.Context) ([]TopicCount, error) {
	rows, err := s.DB.Query(ctx, `SELECT t.slug, t.name, count(c.id)
		FROM topics t LEFT JOIN cards c ON c.topic = t.slug AND c.status = 'published'
		GROUP BY t.slug, t.name, t.sort_order ORDER BY t.sort_order`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []TopicCount{}
	for rows.Next() {
		var t TopicCount
		if err := rows.Scan(&t.Slug, &t.Name, &t.CardCount); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// EnsureTopics upserts the fixed topic list.
func (s *Store) EnsureTopics(ctx context.Context) error {
	for i, t := range content.Topics {
		if _, err := s.DB.Exec(ctx, `INSERT INTO topics (slug, name, sort_order) VALUES ($1, $2, $3)
			ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order`, t.Slug, t.Name, i); err != nil {
			return err
		}
	}
	return nil
}

// FeedParams selects a page of the feed.
type FeedParams struct {
	UserID string // optional
	Topics []string
	Day    string // YYYY-MM-DD, seeds the daily shuffle
	Offset int
	Limit  int
}

// Feed returns published cards in the given topics (all when empty): cards the
// user has not read first, then a shuffle that changes once a day.
func (s *Store) Feed(ctx context.Context, p FeedParams) ([]Card, error) {
	if p.Topics == nil {
		p.Topics = []string{} // a nil slice is NULL, and cardinality(NULL) is NULL
	}
	var uid any
	if p.UserID != "" {
		uid = p.UserID
	}
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`
		LEFT JOIN card_views v ON v.card_id = c.id AND v.user_id = $1::uuid
		WHERE c.status = 'published' AND (cardinality($2::text[]) = 0 OR c.topic = ANY($2))
		ORDER BY (v.card_id IS NOT NULL), md5(c.id || $3 || coalesce($1::text, '')), c.id
		OFFSET $4 LIMIT $5`, uid, p.Topics, p.Day, p.Offset, p.Limit)
	if err != nil {
		return nil, err
	}
	return collectCards(rows)
}

// DailyCard picks one card for the day, preferring unread cards in the user's topics.
func (s *Store) DailyCard(ctx context.Context, userID string, topics []string, day string) (Card, error) {
	cards, err := s.Feed(ctx, FeedParams{UserID: userID, Topics: topics, Day: "daily-" + day, Limit: 1})
	if err != nil {
		return Card{}, err
	}
	if len(cards) == 0 && len(topics) > 0 {
		cards, err = s.Feed(ctx, FeedParams{UserID: userID, Day: "daily-" + day, Limit: 1})
		if err != nil {
			return Card{}, err
		}
	}
	if len(cards) == 0 {
		return Card{}, ErrNotFound
	}
	return cards[0], nil
}

// RecordView marks a card as read by the user.
func (s *Store) RecordView(ctx context.Context, userID, cardID string) error {
	tag, err := s.DB.Exec(ctx, `INSERT INTO card_views (user_id, card_id)
		SELECT $1, id FROM cards WHERE id = $2 AND status = 'published'
		ON CONFLICT (user_id, card_id) DO UPDATE SET viewed_at = now()`, userID, cardID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// HashCard fingerprints a card's content so re-seeding can tell what changed.
func HashCard(src content.Source, c content.Card) string {
	b, _ := json.Marshal(struct {
		C content.Card
		A string
	}{c, src.Attribution})
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// UpsertSource inserts or updates a source row.
func upsertSource(ctx context.Context, tx pgx.Tx, src content.Source) error {
	lang := src.Language
	if lang == "" {
		lang = "en"
	}
	_, err := tx.Exec(ctx, `INSERT INTO sources (id, title, authors, kind, url, licence, licence_url, attribution,
			publisher, year, language, translator, retrieved_at, notes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NULLIF($9,''),$10,$11,NULLIF($12,''),$13::date,NULLIF($14,''))
		ON CONFLICT (id) DO UPDATE SET title=EXCLUDED.title, authors=EXCLUDED.authors, kind=EXCLUDED.kind,
			url=EXCLUDED.url, licence=EXCLUDED.licence, licence_url=EXCLUDED.licence_url, attribution=EXCLUDED.attribution,
			publisher=EXCLUDED.publisher, year=EXCLUDED.year, language=EXCLUDED.language, translator=EXCLUDED.translator,
			retrieved_at=EXCLUDED.retrieved_at, notes=EXCLUDED.notes, updated_at=now()`,
		src.ID, src.Title, src.Authors, src.Kind, src.URL, src.Licence, src.LicenceURL, src.Attribution,
		src.Publisher, src.Year, lang, src.Translator, src.RetrievedAt, src.Notes)
	return err
}

// upsertCard inserts or updates a card; the embedding is cleared when the content changed.
func upsertCard(ctx context.Context, tx pgx.Tx, src content.Source, c content.Card, contributor any) (changed bool, err error) {
	var quiz []byte
	if c.Quiz != nil {
		if quiz, err = json.Marshal(c.Quiz); err != nil {
			return false, err
		}
	}
	lang := c.Language
	if lang == "" {
		lang = src.Language
	}
	if lang == "" {
		lang = "en"
	}
	tags := c.Tags
	if tags == nil {
		tags = []string{}
	}
	hash := HashCard(src, c)
	var inserted bool
	var prevHash *string
	err = tx.QueryRow(ctx, `WITH prev AS (SELECT content_hash FROM cards WHERE id = $1)
		INSERT INTO cards (id, source_id, topic, tags, title, body, quote, apply_it, locator, health, language, quiz, content_hash, contributed_by)
		VALUES ($1,$2,$3,$4,$5,$6,NULLIF($7,''),$8,NULLIF($9,''),$10,$11,$12,$13,$14)
		ON CONFLICT (id) DO UPDATE SET source_id=EXCLUDED.source_id, topic=EXCLUDED.topic, tags=EXCLUDED.tags,
			title=EXCLUDED.title, body=EXCLUDED.body, quote=EXCLUDED.quote, apply_it=EXCLUDED.apply_it,
			locator=EXCLUDED.locator, health=EXCLUDED.health, language=EXCLUDED.language, quiz=EXCLUDED.quiz,
			content_hash=EXCLUDED.content_hash,
			embedding = CASE WHEN cards.content_hash = EXCLUDED.content_hash THEN cards.embedding END,
			embedding_model = CASE WHEN cards.content_hash = EXCLUDED.content_hash THEN cards.embedding_model END,
			updated_at = CASE WHEN cards.content_hash = EXCLUDED.content_hash THEN cards.updated_at ELSE now() END
		RETURNING (xmax = 0), (SELECT content_hash FROM prev)`,
		c.ID, src.ID, c.Topic, tags, c.Title, c.Body, c.Quote, c.ApplyIt, c.Locator, c.Health || c.Topic == "health", lang, quiz, hash, contributor,
	).Scan(&inserted, &prevHash)
	if err != nil {
		return false, err
	}
	return inserted || prevHash == nil || *prevHash != hash, nil
}

// SeedResult summarises an import.
type SeedResult struct {
	Sources int
	Cards   int
	Changed int
}

// Seed upserts every source and card in the library in one transaction.
// Cards that disappeared from a source's file are hidden, not deleted, so
// stashes and reviews that point at them keep working.
func (s *Store) Seed(ctx context.Context, lib content.Library) (SeedResult, error) {
	var res SeedResult
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		for _, f := range lib.Files {
			if err := upsertSource(ctx, tx, f.Source); err != nil {
				return fmt.Errorf("source %s: %w", f.Source.ID, err)
			}
			res.Sources++
			ids := make([]string, 0, len(f.Cards))
			for _, c := range f.Cards {
				changed, err := upsertCard(ctx, tx, f.Source, c, nil)
				if err != nil {
					return fmt.Errorf("card %s: %w", c.ID, err)
				}
				res.Cards++
				if changed {
					res.Changed++
				}
				ids = append(ids, c.ID)
			}
			if _, err := tx.Exec(ctx, `UPDATE cards SET status = CASE WHEN id = ANY($2) THEN 'published' ELSE 'hidden' END
				WHERE source_id = $1 AND contributed_by IS NULL`, f.Source.ID, ids); err != nil {
				return err
			}
		}
		return nil
	})
	return res, err
}

// embedText is what gets embedded for a card.
func embedText(title, body, applyIt string, tags []string, sourceTitle string) string {
	return strings.Join([]string{title, body, "Apply it: " + applyIt, "Tags: " + strings.Join(tags, ", "), "Source: " + sourceTitle}, "\n")
}
