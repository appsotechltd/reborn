package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// trendScore weighs what people did with a post since $since.
const trendScore = `(
	(SELECT count(*) FROM reactions x WHERE x.card_id = c.id AND x.created_at >= $1) +
	2 * (SELECT count(*) FROM comments x WHERE x.card_id = c.id AND x.created_at >= $1 AND x.status = 'visible') +
	2 * (SELECT count(*) FROM favorites x WHERE x.card_id = c.id AND x.created_at >= $1) +
	3 * (SELECT count(*) FROM shares x WHERE x.card_id = c.id AND x.created_at >= $1) +
	5 * (SELECT count(*) FROM gifts x WHERE x.card_id = c.id AND x.paid_at >= $1 AND x.status = 'paid'))`

// Trending returns the posts with the most activity since since, optionally in one topic.
func (s *Store) Trending(ctx context.Context, viewerID, topic string, since time.Time, limit int) ([]Post, error) {
	return s.queryPosts(ctx, viewerID, `SELECT `+postCols+postFrom+`
		WHERE c.status = 'published' AND `+everyoneOnly+` AND ($2 = '' OR c.topic = $2) AND `+trendScore+` > 0
		ORDER BY `+trendScore+` DESC, c.published_at DESC, c.id LIMIT $3`, since, topic, limit)
}

// NewPosts returns the most recently published posts.
func (s *Store) NewPosts(ctx context.Context, viewerID string, limit int) ([]Post, error) {
	return s.queryPosts(ctx, viewerID, `SELECT `+postCols+postFrom+`
		WHERE c.status = 'published' AND `+everyoneOnly+` ORDER BY c.published_at DESC, md5(c.id || current_date::text) LIMIT $1`, limit)
}

// PopularSource is a book with its follower count.
type PopularSource struct {
	SourceSummary
	Followers int `json:"followers"`
}

// PopularSources returns the most followed books.
func (s *Store) PopularSources(ctx context.Context, limit int) ([]PopularSource, error) {
	rows, err := s.DB.Query(ctx, `SELECT s.id, s.title, s.authors, s.kind, s.licence, s.attribution,
			array_agg(DISTINCT c.topic ORDER BY c.topic), count(DISTINCT c.id), greatest(s.updated_at, max(c.updated_at)),
			(SELECT count(*) FROM follows f WHERE f.kind = 'source' AND f.target = s.id) AS followers
		FROM sources s JOIN cards c ON c.source_id = s.id AND c.status = 'published' AND c.author_id IS NULL
		GROUP BY s.id ORDER BY followers DESC, count(DISTINCT c.id) DESC, lower(s.title) LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (PopularSource, error) {
		var x PopularSource
		err := r.Scan(&x.ID, &x.Title, &x.Authors, &x.Kind, &x.Licence, &x.Attribution, &x.Topics, &x.CardCount, &x.UpdatedAt, &x.Followers)
		return x, err
	})
}

// PopularAuthor is an author with follower and book counts.
type PopularAuthor struct {
	Name      string `json:"name"`
	Followers int    `json:"followers"`
	Sources   int    `json:"sources"`
}

// PopularAuthors returns the most followed authors.
func (s *Store) PopularAuthors(ctx context.Context, limit int) ([]PopularAuthor, error) {
	rows, err := s.DB.Query(ctx, `SELECT a.name, (SELECT count(*) FROM follows f WHERE f.kind = 'author' AND f.target = a.name) AS followers,
			count(DISTINCT a.source_id)
		FROM (SELECT unnest(s.authors) AS name, s.id AS source_id FROM sources s
			WHERE EXISTS (SELECT 1 FROM cards c WHERE c.source_id = s.id AND c.status = 'published')) a
		GROUP BY a.name ORDER BY followers DESC, count(DISTINCT a.source_id) DESC, a.name LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[PopularAuthor])
}
