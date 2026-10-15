package store

import (
	"context"
	"sort"

	"github.com/appsotechltd/reborn/backend/internal/embed"
	"github.com/pgvector/pgvector-go"
)

// SearchParams selects cards matching a free-text query.
type SearchParams struct {
	Query string
	Topic string
	Limit int
	// QueryVector, when set, adds semantic matches to keyword matches.
	QueryVector []float32
}

// Search runs keyword search (Postgres full text, any word matches, more
// matches rank higher) and, when a query vector is
// given, vector search (pgvector), and merges them with reciprocal rank fusion.
func (s *Store) Search(ctx context.Context, p SearchParams) ([]Card, error) {
	if p.Limit <= 0 {
		p.Limit = 20
	}
	pool := p.Limit * 3
	keyword, err := s.keywordIDs(ctx, p.Query, p.Topic, pool)
	if err != nil {
		return nil, err
	}
	lists := [][]string{keyword}
	if len(p.QueryVector) == embed.Dimensions {
		semantic, err := s.vectorIDs(ctx, p.QueryVector, p.Topic, pool)
		if err != nil {
			return nil, err
		}
		lists = append(lists, semantic)
	}
	ids := fuse(lists, p.Limit)
	if len(ids) == 0 {
		return []Card{}, nil
	}
	return s.GetCards(ctx, ids)
}

func (s *Store) keywordIDs(ctx context.Context, q, topic string, limit int) ([]string, error) {
	rows, err := s.DB.Query(ctx, `
		WITH q AS (SELECT replace(websearch_to_tsquery('english', $1)::text, ' & ', ' | ')::tsquery AS ts)
		SELECT c.id FROM cards c, q
		WHERE c.status = 'published' AND c.author_id IS NULL AND ($2 = '' OR c.topic = $2)
		  AND (c.search @@ q.ts OR c.title ILIKE '%' || $1 || '%' OR $1 = ANY(c.tags))
		ORDER BY ts_rank_cd(c.search, q.ts) DESC, c.id
		LIMIT $3`, q, topic, limit)
	if err != nil {
		return nil, err
	}
	return collectIDs(rows)
}

func (s *Store) vectorIDs(ctx context.Context, vec []float32, topic string, limit int) ([]string, error) {
	rows, err := s.DB.Query(ctx, `SELECT id FROM cards
		WHERE status = 'published' AND author_id IS NULL AND embedding IS NOT NULL AND ($2 = '' OR topic = $2)
		ORDER BY embedding <=> $1 LIMIT $3`, pgvector.NewVector(vec), topic, limit)
	if err != nil {
		return nil, err
	}
	return collectIDs(rows)
}

func collectIDs(rows interface {
	Next() bool
	Scan(...any) error
	Err() error
	Close()
}) ([]string, error) {
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// fuse merges ranked id lists with reciprocal rank fusion (k = 60).
func fuse(lists [][]string, limit int) []string {
	score := map[string]float64{}
	first := map[string]int{}
	n := 0
	for _, list := range lists {
		for rank, id := range list {
			score[id] += 1.0 / float64(60+rank+1)
			if _, ok := first[id]; !ok {
				first[id] = n
				n++
			}
		}
	}
	ids := make([]string, 0, len(score))
	for id := range score {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool {
		if score[ids[i]] != score[ids[j]] {
			return score[ids[i]] > score[ids[j]]
		}
		return first[ids[i]] < first[ids[j]]
	})
	if len(ids) > limit {
		ids = ids[:limit]
	}
	return ids
}

// CardsMissingEmbeddings returns up to limit published cards without an
// embedding for model, with the text to embed.
func (s *Store) CardsMissingEmbeddings(ctx context.Context, model string, limit int) (ids, texts []string, err error) {
	rows, err := s.DB.Query(ctx, `SELECT c.id, c.title, c.body, c.apply_it, c.tags, s.title
		FROM cards c JOIN sources s ON s.id = c.source_id
		WHERE c.status = 'published' AND c.author_id IS NULL AND (c.embedding IS NULL OR c.embedding_model IS DISTINCT FROM $1)
		ORDER BY c.id LIMIT $2`, model, limit)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, title, body, apply, srcTitle string
		var tags []string
		if err := rows.Scan(&id, &title, &body, &apply, &tags, &srcTitle); err != nil {
			return nil, nil, err
		}
		ids = append(ids, id)
		texts = append(texts, embedText(title, body, apply, tags, srcTitle))
	}
	return ids, texts, rows.Err()
}

// SetEmbedding stores a card's vector.
func (s *Store) SetEmbedding(ctx context.Context, id, model string, vec []float32) error {
	_, err := s.DB.Exec(ctx, `UPDATE cards SET embedding = $2, embedding_model = $3 WHERE id = $1`, id, pgvector.NewVector(vec), model)
	return err
}

// EmbedMissing embeds every card that lacks a vector for e's model.
func (s *Store) EmbedMissing(ctx context.Context, e embed.Embedder) (int, error) {
	total := 0
	for {
		ids, texts, err := s.CardsMissingEmbeddings(ctx, e.Model(), 64)
		if err != nil || len(ids) == 0 {
			return total, err
		}
		vecs, err := e.Embed(ctx, texts, "document")
		if err != nil {
			return total, err
		}
		for i, id := range ids {
			if err := s.SetEmbedding(ctx, id, e.Model(), vecs[i]); err != nil {
				return total, err
			}
		}
		total += len(ids)
	}
}
