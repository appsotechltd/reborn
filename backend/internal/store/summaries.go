package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/cardimages"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/jackc/pgx/v5"
)

// Summary is a full summary post: a whole book or topic read part by part.
// Every part is a card; Parts are loaded only by GetSummary.
type Summary struct {
	ID          string `json:"id"`
	Kind        string `json:"kind"` // book or topic
	Title       string `json:"title"`
	Description string `json:"description"`
	Topic       string `json:"topic"`
	TopicName   string `json:"topic_name"`
	// Coverage is "full" for a book we may cover in full (public domain and
	// open licences), "key-ideas" for an in-copyright book summarised in our
	// own words, "guide" for one of our own complete guides (a source of kind
	// guide), and "topic" for a topic summary.
	Coverage string `json:"coverage"`
	// Source is the book, for book summaries.
	Source      *SourceRef       `json:"source,omitempty"`
	Authors     []string         `json:"authors"`
	SourceCount int              `json:"source_count"`
	PartCount   int              `json:"part_count"`
	Minutes     int              `json:"minutes"`
	PublishedAt time.Time        `json:"published_at"`
	Viewer      *SummaryProgress `json:"viewer,omitempty"`
	// Cover is a guide's cover picture (its first part's image), when it has one.
	Cover *cardimages.Image `json:"cover,omitempty"`
}

// SummaryProgress is where the signed-in reader is in a summary.
type SummaryProgress struct {
	Started  bool `json:"started"`
	Position int  `json:"position"` // zero-based part index
	Finished bool `json:"finished"`
}

// SummaryDetail is a summary with its parts, in reading order.
type SummaryDetail struct {
	Summary
	Parts []Card `json:"parts"`
}

// ErrBadPosition is returned for a progress position outside the summary's parts.
var ErrBadPosition = errors.New("position is outside the summary")

// ReadingWordsPerMinute turns a summary's word count into minutes.
const ReadingWordsPerMinute = 200

const summaryCols = `sm.id, sm.kind, sm.title, sm.description, sm.topic, t.name, sm.authors,
	cardinality(sm.source_ids), cardinality(sm.card_ids), sm.words, sm.published_at,
	s.id, s.title, s.authors, s.kind, s.url, s.licence, s.licence_url, s.attribution,
	p.user_id IS NOT NULL, coalesce(p.position, 0), p.finished_at IS NOT NULL, coalesce(sm.card_ids[1], '')`

// summaryFrom joins the viewer's progress; $1 is the viewer's id or NULL.
const summaryFrom = ` FROM summaries sm JOIN topics t ON t.slug = sm.topic
	LEFT JOIN sources s ON s.id = sm.source_id
	LEFT JOIN summary_progress p ON p.summary_id = sm.id AND p.user_id = $1::uuid `

func scanSummary(row pgx.Row, viewer bool) (Summary, error) {
	var sm Summary
	var words int
	var srcID, srcTitle, srcKind, srcURL, srcLicence, srcLicenceURL, srcAttribution *string
	var srcAuthors []string
	var p SummaryProgress
	var firstCard string
	err := row.Scan(&sm.ID, &sm.Kind, &sm.Title, &sm.Description, &sm.Topic, &sm.TopicName, &sm.Authors,
		&sm.SourceCount, &sm.PartCount, &words, &sm.PublishedAt,
		&srcID, &srcTitle, &srcAuthors, &srcKind, &srcURL, &srcLicence, &srcLicenceURL, &srcAttribution,
		&p.Started, &p.Position, &p.Finished, &firstCard)
	if err != nil {
		return sm, err
	}
	sm.Minutes = max(1, (words+ReadingWordsPerMinute-1)/ReadingWordsPerMinute)
	if sm.Authors == nil {
		sm.Authors = []string{}
	}
	sm.Coverage = "topic"
	if srcID != nil {
		sm.Source = &SourceRef{ID: *srcID, Title: *srcTitle, Authors: srcAuthors, Kind: *srcKind, URL: *srcURL,
			Licence: *srcLicence, LicenceURL: *srcLicenceURL, Attribution: *srcAttribution}
		sm.Coverage = "full"
		if *srcKind == "guide" {
			sm.Coverage = "guide"
			sm.Cover = imageFor(firstCard)
		} else if !content.Licences[*srcLicence] {
			sm.Coverage = "key-ideas"
		}
	}
	if viewer {
		sm.Viewer = &p
	}
	return sm, nil
}

func collectSummaries(rows pgx.Rows, viewer bool) ([]Summary, error) {
	defer rows.Close()
	out := []Summary{}
	for rows.Next() {
		sm, err := scanSummary(rows, viewer)
		if err != nil {
			return nil, err
		}
		out = append(out, sm)
	}
	return out, rows.Err()
}

func nullableUser(id string) any {
	if id == "" {
		return nil
	}
	return id
}

// SummaryFeedParams selects the summaries woven into a timeline.
type SummaryFeedParams struct {
	UserID string
	Topics []string
	// TopicsOnly ignores follows (the timeline is filtered to one topic).
	TopicsOnly bool
	Day        string
	// Snapshot: reading after this doesn't reorder the pages being scrolled.
	Snapshot time.Time
	Offset   int
	Limit    int
}

// SummaryFeed returns summaries for someone's timeline: those in their topics
// or from books and authors they follow (everything when they have neither),
// ones they haven't started first, then ones they're partway through, then
// ones they finished.
func (s *Store) SummaryFeed(ctx context.Context, p SummaryFeedParams) ([]Summary, error) {
	if p.Topics == nil {
		p.Topics = []string{}
	}
	rows, err := s.DB.Query(ctx, `WITH f AS (
			SELECT kind, target FROM follows
			WHERE follower_id = $1::uuid AND kind IN ('source', 'author') AND NOT $7
		), unfiltered AS (
			SELECT cardinality($2::text[]) = 0 AND NOT EXISTS (SELECT 1 FROM f) AS yes
		)
		SELECT `+summaryCols+summaryFrom+`
		WHERE sm.status = 'published' AND (
			(SELECT yes FROM unfiltered) OR sm.topic = ANY($2)
			OR sm.source_id IN (SELECT target FROM f WHERE kind = 'source')
			OR sm.authors && ARRAY(SELECT target FROM f WHERE kind = 'author'))
		ORDER BY CASE WHEN p.started_at IS NULL OR p.started_at >= $4 THEN 0
				WHEN p.finished_at IS NULL OR p.finished_at >= $4 THEN 1 ELSE 2 END,
			sm.published_at DESC, md5(sm.id || $3 || coalesce($1::text, '')), sm.id
		OFFSET $5 LIMIT $6`, nullableUser(p.UserID), p.Topics, p.Day, p.Snapshot, p.Offset, p.Limit, p.TopicsOnly)
	if err != nil {
		return nil, err
	}
	return collectSummaries(rows, p.UserID != "")
}

// SummaryListParams filters the summaries browse list.
type SummaryListParams struct {
	UserID string
	Kind   string // book, topic or ""
	Topic  string
	Source string
	Offset int
	Limit  int
}

// Summaries lists published summaries: topic summaries first, then books, by title.
func (s *Store) Summaries(ctx context.Context, p SummaryListParams) ([]Summary, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+summaryCols+summaryFrom+`
		WHERE sm.status = 'published' AND ($2 = '' OR sm.kind = $2) AND ($3 = '' OR sm.topic = $3)
			AND ($4 = '' OR $4 = ANY(sm.source_ids))
		ORDER BY sm.kind DESC, lower(sm.title), sm.id OFFSET $5 LIMIT $6`,
		nullableUser(p.UserID), p.Kind, p.Topic, p.Source, p.Offset, p.Limit)
	if err != nil {
		return nil, err
	}
	return collectSummaries(rows, p.UserID != "")
}

// GetSummary returns a published summary with its published parts in order.
func (s *Store) GetSummary(ctx context.Context, id, userID string) (SummaryDetail, error) {
	sm, err := scanSummary(s.DB.QueryRow(ctx, `SELECT `+summaryCols+summaryFrom+`
		WHERE sm.id = $2 AND sm.status = 'published'`, nullableUser(userID), id), userID != "")
	if err != nil {
		return SummaryDetail{}, notFound(err)
	}
	var cardIDs []string
	if err := s.DB.QueryRow(ctx, `SELECT card_ids FROM summaries WHERE id = $1`, id).Scan(&cardIDs); err != nil {
		return SummaryDetail{}, err
	}
	parts, err := s.GetCards(ctx, cardIDs)
	if err != nil {
		return SummaryDetail{}, err
	}
	sm.PartCount = len(parts)
	if sm.Viewer != nil && sm.Viewer.Position >= len(parts) {
		sm.Viewer.Position = max(0, len(parts)-1)
	}
	return SummaryDetail{Summary: sm, Parts: parts}, nil
}

// SourceSummaryID returns the id of a source's book summary, or "" when it has none.
func (s *Store) SourceSummaryID(ctx context.Context, sourceID string) (string, error) {
	var id string
	err := s.DB.QueryRow(ctx, `SELECT id FROM summaries WHERE source_id = $1 AND kind = 'book' AND status = 'published'`,
		sourceID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	return id, err
}

// SetSummaryProgress records where a reader is in a summary. Finishing is kept
// once reached, so going back to reread a part doesn't undo it.
func (s *Store) SetSummaryProgress(ctx context.Context, userID, id string, position int, finished bool, now time.Time) (SummaryProgress, error) {
	var parts int
	err := s.DB.QueryRow(ctx, `SELECT cardinality(card_ids) FROM summaries WHERE id = $1 AND status = 'published'`, id).Scan(&parts)
	if err != nil {
		return SummaryProgress{}, notFound(err)
	}
	if position < 0 || position >= parts {
		return SummaryProgress{}, ErrBadPosition
	}
	p := SummaryProgress{Started: true}
	err = s.DB.QueryRow(ctx, `INSERT INTO summary_progress (user_id, summary_id, position, started_at, finished_at, updated_at)
		VALUES ($1, $2, $3, $5, CASE WHEN $4 THEN $5::timestamptz END, $5)
		ON CONFLICT (user_id, summary_id) DO UPDATE SET position = EXCLUDED.position, updated_at = EXCLUDED.updated_at,
			finished_at = coalesce(summary_progress.finished_at, EXCLUDED.finished_at)
		RETURNING position, finished_at IS NOT NULL`, userID, id, position, finished, now).Scan(&p.Position, &p.Finished)
	return p, err
}

// seedSummaries builds a book summary for every source with enough cards,
// upserts the topic summaries, and hides summaries no longer in the library.
func seedSummaries(ctx context.Context, tx pgx.Tx, lib content.Library) (int, error) {
	type row struct {
		id, kind, title, description, topic string
		sourceID                            any
		sourceIDs, authors, cardIDs         []string
		words                               int
	}
	var rows []row
	cardByID := map[string]content.Card{}
	sourceOf := map[string]content.Source{}
	for _, f := range lib.Files {
		for _, c := range f.Cards {
			cardByID[c.ID] = c
			sourceOf[c.ID] = f.Source
		}
		if len(f.Cards) < content.MinSummaryParts {
			continue
		}
		r := row{id: f.Source.ID, kind: "book", title: f.Source.Title, topic: mainTopic(f.Cards),
			sourceID: f.Source.ID, sourceIDs: []string{f.Source.ID}, authors: f.Source.Authors}
		for _, c := range f.Cards {
			r.cardIDs = append(r.cardIDs, c.ID)
			r.words += partWords(c)
		}
		if content.Licences[f.Source.Licence] {
			r.description = fmt.Sprintf("Every idea from %s, in %d one-minute parts.", f.Source.Title, len(f.Cards))
		} else {
			r.description = fmt.Sprintf("The %d key ideas from %s, in our own words.", len(f.Cards), f.Source.Title)
		}
		rows = append(rows, r)
	}
	for _, ts := range lib.Summaries {
		r := row{id: ts.ID, kind: "topic", title: ts.Title, description: ts.Description, topic: ts.Topic,
			sourceIDs: []string{}, authors: []string{}, cardIDs: ts.Cards}
		seenSrc, seenAuthor := map[string]bool{}, map[string]bool{}
		for _, id := range ts.Cards {
			r.words += partWords(cardByID[id])
			src := sourceOf[id]
			if !seenSrc[src.ID] {
				seenSrc[src.ID] = true
				r.sourceIDs = append(r.sourceIDs, src.ID)
			}
			for _, a := range src.Authors {
				if !seenAuthor[a] {
					seenAuthor[a] = true
					r.authors = append(r.authors, a)
				}
			}
		}
		rows = append(rows, r)
	}
	ids := make([]string, 0, len(rows))
	for _, r := range rows {
		if _, err := tx.Exec(ctx, `INSERT INTO summaries (id, kind, title, description, topic, source_id, source_ids, authors, card_ids, words)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
			ON CONFLICT (id) DO UPDATE SET kind=EXCLUDED.kind, title=EXCLUDED.title, description=EXCLUDED.description,
				topic=EXCLUDED.topic, source_id=EXCLUDED.source_id, source_ids=EXCLUDED.source_ids, authors=EXCLUDED.authors,
				card_ids=EXCLUDED.card_ids, words=EXCLUDED.words, status='published',
				updated_at = CASE WHEN summaries.card_ids = EXCLUDED.card_ids AND summaries.title = EXCLUDED.title
					AND summaries.description = EXCLUDED.description THEN summaries.updated_at ELSE now() END`,
			r.id, r.kind, r.title, r.description, r.topic, r.sourceID, r.sourceIDs, r.authors, r.cardIDs, r.words); err != nil {
			return 0, fmt.Errorf("summary %s: %w", r.id, err)
		}
		ids = append(ids, r.id)
	}
	_, err := tx.Exec(ctx, `UPDATE summaries SET status = 'hidden' WHERE NOT (id = ANY($1))`, ids)
	return len(rows), err
}

// mainTopic is the topic most of a source's cards share (the earliest wins a tie).
func mainTopic(cards []content.Card) string {
	n := map[string]int{}
	best := ""
	for _, c := range cards {
		n[c.Topic]++
		if best == "" || n[c.Topic] > n[best] {
			best = c.Topic
		}
	}
	return best
}

func partWords(c content.Card) int {
	return content.WordCount(c.Title) + content.WordCount(c.Body) + content.WordCount(c.ApplyIt)
}

// SitemapSummaries lists every published summary.
func (s *Store) SitemapSummaries(ctx context.Context) ([]SitemapEntry, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, updated_at FROM summaries WHERE status = 'published' ORDER BY id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (SitemapEntry, error) {
		var e SitemapEntry
		err := r.Scan(&e.ID, &e.UpdatedAt)
		return e, err
	})
}
