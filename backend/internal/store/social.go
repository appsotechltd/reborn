package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Reactions are the kinds of reaction a post can get.
var Reactions = []string{"like", "love", "insightful", "inspiring", "helpful"}

// IsReaction reports whether k is a known reaction.
func IsReaction(k string) bool {
	for _, r := range Reactions {
		if r == k {
			return true
		}
	}
	return false
}

// Profile is the public view of a user.
type Profile struct {
	ID          string `json:"id"`
	Handle      string `json:"handle"`
	DisplayName string `json:"display_name"`
}

// PostStats counts what people did with a post.
type PostStats struct {
	Reactions map[string]int `json:"reactions"`
	Comments  int            `json:"comments"`
	Favorites int            `json:"favorites"`
	Shares    int            `json:"shares"`
	Gifts     int            `json:"gifts"`
}

// Viewer is the signed-in user's own state on a post.
type Viewer struct {
	Reaction  *string `json:"reaction"`
	Favorited bool    `json:"favorited"`
	Seen      bool    `json:"seen"`
}

// Reason says why a post is in someone's timeline.
type Reason struct {
	Kind  string `json:"kind"` // source, author, favorite, topic, new
	Label string `json:"label"`
}

// Post is a card with its social context. Every published card is a post;
// people react to, favourite, comment on and share posts but never write them.
type Post struct {
	ID          string    `json:"id"`
	PublishedAt time.Time `json:"published_at"`
	Card        Card      `json:"card"`
	Stats       PostStats `json:"stats"`
	Viewer      *Viewer   `json:"viewer,omitempty"`
	Reason      *Reason   `json:"reason,omitempty"`
}

// postCols adds the publish time to cardCols.
const postCols = cardCols + `, c.published_at`

const postFrom = cardFrom

func scanPost(row pgx.Row, extra ...any) (Post, error) {
	var p Post
	c, err := scanCardWith(row, append([]any{&p.PublishedAt}, extra...)...)
	if err != nil {
		return p, err
	}
	p.ID, p.Card = c.ID, c
	return p, nil
}

// TimelineParams selects a page of a timeline.
type TimelineParams struct {
	UserID   string // optional
	Topics   []string
	Day      string    // seeds the shuffle among posts published together
	Snapshot time.Time // views after this don't reorder the pages being scrolled
	Offset   int
	Limit    int
}

// Timeline returns posts from the user's topics, followed books and authors,
// and posts that people they follow favourited: unseen posts first, newest
// first. Without topics or follows it covers everything.
func (s *Store) Timeline(ctx context.Context, p TimelineParams) ([]Post, error) {
	if p.Topics == nil {
		p.Topics = []string{}
	}
	var uid any
	if p.UserID != "" {
		uid = p.UserID
	}
	rows, err := s.DB.Query(ctx, `WITH f AS (
			SELECT kind, target FROM follows WHERE follower_id = $1::uuid
		), fu AS (
			SELECT target::uuid AS id FROM f WHERE kind = 'user'
		), ffav AS (
			SELECT DISTINCT ON (fv.card_id) fv.card_id, u.display_name
			FROM favorites fv JOIN fu ON fu.id = fv.user_id JOIN users u ON u.id = fv.user_id
			WHERE NOT EXISTS (SELECT 1 FROM blocks WHERE user_id = $1::uuid AND blocked_id = fv.user_id)
			ORDER BY fv.card_id, fv.created_at DESC
		), unfiltered AS (
			SELECT cardinality($2::text[]) = 0 AND NOT EXISTS (SELECT 1 FROM f) AS yes
		)
		SELECT `+postCols+`, (v.viewed_at IS NOT NULL AND v.viewed_at < $4) AS seen, r.kind, r.label
		`+postFrom+`
		LEFT JOIN card_views v ON v.card_id = c.id AND v.user_id = $1::uuid
		LEFT JOIN ffav ON ffav.card_id = c.id
		JOIN topics t ON t.slug = c.topic
		CROSS JOIN LATERAL (
			SELECT kind, label FROM (VALUES
				(1, 'source', CASE WHEN c.source_id IN (SELECT target FROM f WHERE kind = 'source') THEN s.title END),
				(2, 'author', (SELECT a FROM unnest(s.authors) a WHERE a IN (SELECT target FROM f WHERE kind = 'author') LIMIT 1)),
				(3, 'favorite', ffav.display_name),
				(4, 'topic', CASE WHEN c.topic = ANY($2) THEN t.name END),
				(5, 'new', CASE WHEN (SELECT yes FROM unfiltered) THEN '' END)
			) AS x(n, kind, label)
			WHERE label IS NOT NULL ORDER BY n LIMIT 1
		) r
		WHERE c.status = 'published'
		ORDER BY seen, c.published_at DESC, md5(c.id || $3 || coalesce($1::text, '')), c.id
		OFFSET $5 LIMIT $6`, uid, p.Topics, p.Day, p.Snapshot, p.Offset, p.Limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Post{}
	for rows.Next() {
		var seen bool
		var reason Reason
		post, err := scanPost(rows, &seen, &reason.Kind, &reason.Label)
		if err != nil {
			return nil, err
		}
		post.Reason = &reason
		if p.UserID != "" {
			post.Viewer = &Viewer{Seen: seen}
		}
		out = append(out, post)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, s.fillPosts(ctx, out, p.UserID)
}

// GetPost returns one published post.
func (s *Store) GetPost(ctx context.Context, id, userID string) (Post, error) {
	posts, err := s.queryPosts(ctx, userID, `SELECT `+postCols+postFrom+`WHERE c.id = $1 AND c.status = 'published'`, id)
	if err != nil {
		return Post{}, err
	}
	if len(posts) == 0 {
		return Post{}, ErrNotFound
	}
	return posts[0], nil
}

// Favorites returns the posts a user favourited, newest first.
func (s *Store) Favorites(ctx context.Context, ownerID, viewerID string, offset, limit int) ([]Post, error) {
	return s.queryPosts(ctx, viewerID, `SELECT `+postCols+postFrom+`
		JOIN favorites fv ON fv.card_id = c.id AND fv.user_id = $1
		WHERE c.status = 'published' ORDER BY fv.created_at DESC, c.id OFFSET $2 LIMIT $3`, ownerID, offset, limit)
}

func (s *Store) queryPosts(ctx context.Context, viewerID, q string, args ...any) ([]Post, error) {
	rows, err := s.DB.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Post{}
	for rows.Next() {
		p, err := scanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if viewerID != "" {
		var seen []string
		ids := postIDs(out)
		r, err := s.DB.Query(ctx, `SELECT card_id FROM card_views WHERE user_id = $1 AND card_id = ANY($2)`, viewerID, ids)
		if err != nil {
			return nil, err
		}
		seen, err = pgx.CollectRows(r, pgx.RowTo[string])
		if err != nil {
			return nil, err
		}
		set := toSet(seen)
		for i := range out {
			out[i].Viewer = &Viewer{Seen: set[out[i].ID]}
		}
	}
	return out, s.fillPosts(ctx, out, viewerID)
}

func postIDs(posts []Post) []string {
	ids := make([]string, len(posts))
	for i, p := range posts {
		ids[i] = p.ID
	}
	return ids
}

func toSet(xs []string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[x] = true
	}
	return m
}

// fillPosts loads counts, and the viewer's reaction and favourite, for a page of posts.
func (s *Store) fillPosts(ctx context.Context, posts []Post, viewerID string) error {
	if len(posts) == 0 {
		return nil
	}
	idx := make(map[string]int, len(posts))
	for i := range posts {
		posts[i].Stats.Reactions = map[string]int{}
		idx[posts[i].ID] = i
	}
	ids := postIDs(posts)
	rows, err := s.DB.Query(ctx, `SELECT card_id, kind, count(*) FROM reactions WHERE card_id = ANY($1) GROUP BY card_id, kind`, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id, kind string
		var n int
		if err := rows.Scan(&id, &kind, &n); err != nil {
			rows.Close()
			return err
		}
		posts[idx[id]].Stats.Reactions[kind] = n
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	rows, err = s.DB.Query(ctx, `SELECT x.pid,
			(SELECT count(*) FROM comments WHERE card_id = x.pid AND status = 'visible'),
			(SELECT count(*) FROM favorites WHERE card_id = x.pid),
			(SELECT count(*) FROM shares WHERE card_id = x.pid),
			(SELECT count(*) FROM gifts WHERE card_id = x.pid AND status = 'paid')
		FROM unnest($1::text[]) AS x(pid)`, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var st PostStats
		if err := rows.Scan(&id, &st.Comments, &st.Favorites, &st.Shares, &st.Gifts); err != nil {
			rows.Close()
			return err
		}
		p := &posts[idx[id]]
		p.Stats.Comments, p.Stats.Favorites, p.Stats.Shares, p.Stats.Gifts = st.Comments, st.Favorites, st.Shares, st.Gifts
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	if viewerID == "" {
		return nil
	}
	rows, err = s.DB.Query(ctx, `SELECT x.pid, r.kind, fv.user_id IS NOT NULL FROM unnest($2::text[]) AS x(pid)
		LEFT JOIN reactions r ON r.card_id = x.pid AND r.user_id = $1
		LEFT JOIN favorites fv ON fv.card_id = x.pid AND fv.user_id = $1`, viewerID, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var kind *string
		var fav bool
		if err := rows.Scan(&id, &kind, &fav); err != nil {
			return err
		}
		p := &posts[idx[id]]
		if p.Viewer == nil {
			p.Viewer = &Viewer{}
		}
		p.Viewer.Reaction, p.Viewer.Favorited = kind, fav
	}
	return rows.Err()
}

// MarkSeen records that the user saw these posts and returns how many were
// new to them; unknown ids are ignored.
func (s *Store) MarkSeen(ctx context.Context, userID string, ids []string, now time.Time) (int, error) {
	tag, err := s.DB.Exec(ctx, `INSERT INTO card_views (user_id, card_id, viewed_at)
		SELECT $1, id, $3 FROM cards WHERE id = ANY($2) AND status = 'published'
		ON CONFLICT (user_id, card_id) DO NOTHING`, userID, ids, now)
	return int(tag.RowsAffected()), err
}

// postExists returns ErrNotFound unless the card is published.
func (s *Store) postExists(ctx context.Context, id string) error {
	var ok bool
	if err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM cards WHERE id = $1 AND status = 'published')`, id).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}
	return nil
}

// SetFavorite adds or removes a favourite.
func (s *Store) SetFavorite(ctx context.Context, userID, cardID string, on bool) error {
	if err := s.postExists(ctx, cardID); err != nil {
		return err
	}
	var err error
	if on {
		_, err = s.DB.Exec(ctx, `INSERT INTO favorites (user_id, card_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, userID, cardID)
	} else {
		_, err = s.DB.Exec(ctx, `DELETE FROM favorites WHERE user_id = $1 AND card_id = $2`, userID, cardID)
	}
	return err
}

// SetReaction sets the user's reaction on a post, or clears it when kind is "".
func (s *Store) SetReaction(ctx context.Context, userID, cardID, kind string) error {
	if err := s.postExists(ctx, cardID); err != nil {
		return err
	}
	var err error
	if kind != "" {
		_, err = s.DB.Exec(ctx, `INSERT INTO reactions (user_id, card_id, kind) VALUES ($1, $2, $3)
			ON CONFLICT (user_id, card_id) DO UPDATE SET kind = EXCLUDED.kind, created_at = now()`, userID, cardID, kind)
	} else {
		_, err = s.DB.Exec(ctx, `DELETE FROM reactions WHERE user_id = $1 AND card_id = $2`, userID, cardID)
	}
	return err
}

// RecordShare counts a share of a post.
func (s *Store) RecordShare(ctx context.Context, userID, cardID, channel string) error {
	var uid any
	if userID != "" {
		uid = userID
	}
	tag, err := s.DB.Exec(ctx, `INSERT INTO shares (card_id, user_id, channel)
		SELECT id, $2, $3 FROM cards WHERE id = $1 AND status = 'published'`, cardID, uid, channel)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
