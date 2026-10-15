package store

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// FollowKinds are the things a user can follow. Topics are interests, set on the user.
var FollowKinds = []string{"user", "source", "author"}

// Follow is one thing a user follows.
type Follow struct {
	Kind   string `json:"kind"`
	Target string `json:"target"` // user id, source id or author name
	Label  string `json:"label"`  // display name, book title or author name
	Handle string `json:"handle,omitempty"`
}

// UserProfile is a public profile with follow counts.
type UserProfile struct {
	Profile
	Bio         string `json:"bio"`
	Followers   int    `json:"followers"`
	Following   int    `json:"following"`
	Favorites   int    `json:"favorites"`
	Cards       int    `json:"cards"` // cards they wrote that the viewer may see
	IsFollowing bool   `json:"is_following"`
	IsMe        bool   `json:"is_me"`
}

// SetFollow follows or unfollows a target, checking that it exists.
func (s *Store) SetFollow(ctx context.Context, userID, kind, target string, on bool) error {
	if !on {
		_, err := s.DB.Exec(ctx, `DELETE FROM follows WHERE follower_id = $1 AND kind = $2 AND target = $3`, userID, kind, target)
		return err
	}
	var q string
	switch kind {
	case "user":
		if target == userID {
			return ErrConflict
		}
		if blocked, err := s.isBlockedBy(ctx, target, userID); err != nil || blocked {
			if err == nil {
				err = ErrBlocked
			}
			return err
		}
		q = `SELECT EXISTS (SELECT 1 FROM users WHERE id::text = $1)`
	case "source":
		q = `SELECT EXISTS (SELECT 1 FROM sources WHERE id = $1)`
	case "author":
		q = `SELECT EXISTS (SELECT 1 FROM sources WHERE $1 = ANY(authors))`
	default:
		return ErrNotFound
	}
	var ok bool
	if err := s.DB.QueryRow(ctx, q, target).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}
	_, err := s.DB.Exec(ctx, `INSERT INTO follows (follower_id, kind, target) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, userID, kind, target)
	return err
}

// Following lists what a user follows, newest first.
func (s *Store) Following(ctx context.Context, userID string) ([]Follow, error) {
	rows, err := s.DB.Query(ctx, `SELECT f.kind, f.target,
			coalesce(u.display_name, src.title, f.target), coalesce(u.handle, '')
		FROM follows f
		LEFT JOIN users u ON f.kind = 'user' AND u.id::text = f.target
		LEFT JOIN sources src ON f.kind = 'source' AND src.id = f.target
		WHERE f.follower_id = $1 ORDER BY f.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Follow, error) {
		var f Follow
		err := r.Scan(&f.Kind, &f.Target, &f.Label, &f.Handle)
		return f, err
	})
}

// Followers lists the users who follow a target.
func (s *Store) Followers(ctx context.Context, kind, target string, offset, limit int) ([]Profile, error) {
	rows, err := s.DB.Query(ctx, `SELECT u.id::text, u.handle, u.display_name FROM follows f
		JOIN users u ON u.id = f.follower_id WHERE f.kind = $1 AND f.target = $2
		ORDER BY f.created_at DESC OFFSET $3 LIMIT $4`, kind, target, offset, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Profile, error) {
		var p Profile
		err := r.Scan(&p.ID, &p.Handle, &p.DisplayName)
		return p, err
	})
}

// FollowState is a target's follower count and whether the viewer follows it.
type FollowState struct {
	Followers   int  `json:"followers"`
	IsFollowing bool `json:"is_following"`
}

// FollowStateOf returns a target's follower count and whether viewerID follows it.
func (s *Store) FollowStateOf(ctx context.Context, kind, target, viewerID string) (FollowState, error) {
	var st FollowState
	var vid any
	if viewerID != "" {
		vid = viewerID
	}
	err := s.DB.QueryRow(ctx, `SELECT count(*), coalesce(bool_or(follower_id = $3::uuid), false)
		FROM follows WHERE kind = $1 AND target = $2`, kind, target, vid).Scan(&st.Followers, &st.IsFollowing)
	return st, err
}

// ProfileByHandle returns a public profile.
func (s *Store) ProfileByHandle(ctx context.Context, handle, viewerID string) (UserProfile, error) {
	var p UserProfile
	var vid any
	if viewerID != "" {
		vid = viewerID
	}
	err := s.DB.QueryRow(ctx, `SELECT u.id::text, u.handle, u.display_name, u.bio,
			(SELECT count(*) FROM follows WHERE kind = 'user' AND target = u.id::text),
			(SELECT count(*) FROM follows WHERE follower_id = u.id),
			(SELECT count(*) FROM favorites WHERE user_id = u.id),
			(SELECT count(*) FROM cards c WHERE c.author_id = u.id AND c.status = 'published' AND `+visibleTo("$2")+`),
			EXISTS (SELECT 1 FROM follows WHERE follower_id = $2::uuid AND kind = 'user' AND target = u.id::text),
			(u.id = $2::uuid) IS TRUE
		FROM users u WHERE lower(u.handle) = lower($1)
		AND NOT EXISTS (SELECT 1 FROM blocks WHERE user_id = u.id AND blocked_id = $2::uuid AND kind = 'block')`, handle, vid).
		Scan(&p.ID, &p.Handle, &p.DisplayName, &p.Bio, &p.Followers, &p.Following, &p.Favorites, &p.Cards, &p.IsFollowing, &p.IsMe)
	return p, notFound(err)
}

// AuthorPage is an author with their sources and every published card from them.
type AuthorPage struct {
	Name       string          `json:"name"`
	Sources    []SourceSummary `json:"sources"`
	Cards      []Card          `json:"cards"`
	CardCount  int             `json:"card_count"`
	VideoCount int             `json:"video_count"`
	FollowState
}

// Author returns the sources by an author name, with follow state.
func (s *Store) Author(ctx context.Context, name, viewerID string) (AuthorPage, error) {
	a := AuthorPage{Name: name}
	rows, err := s.DB.Query(ctx, `SELECT s.id, s.title, s.authors, s.kind, s.licence, s.attribution,
			array_agg(DISTINCT c.topic ORDER BY c.topic), count(c.id), greatest(s.updated_at, max(c.updated_at))
		FROM sources s JOIN cards c ON c.source_id = s.id AND c.status = 'published' AND c.author_id IS NULL
		WHERE $1 = ANY(s.authors) GROUP BY s.id ORDER BY lower(s.title)`, name)
	if err != nil {
		return a, err
	}
	videos := videoCounts()
	a.Sources, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (SourceSummary, error) {
		var x SourceSummary
		err := r.Scan(&x.ID, &x.Title, &x.Authors, &x.Kind, &x.Licence, &x.Attribution, &x.Topics, &x.CardCount, &x.UpdatedAt)
		x.VideoCount = videos[x.ID]
		return x, err
	})
	if err != nil {
		return a, err
	}
	if len(a.Sources) == 0 {
		return a, ErrNotFound
	}
	for _, src := range a.Sources {
		a.CardCount += src.CardCount
		a.VideoCount += src.VideoCount
	}
	cardRows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`WHERE $1 = ANY(s.authors) AND c.status = 'published'
		ORDER BY lower(s.title), c.id`, name)
	if err != nil {
		return a, err
	}
	if a.Cards, err = collectCards(cardRows); err != nil {
		return a, err
	}
	a.FollowState, err = s.FollowStateOf(ctx, "author", name, viewerID)
	return a, err
}

// AuthorSummary is an author in the authors list.
type AuthorSummary struct {
	Name       string   `json:"name"`
	Sources    int      `json:"sources"`
	CardCount  int      `json:"card_count"`
	VideoCount int      `json:"video_count"`
	Topics     []string `json:"topics"`
	Followers  int      `json:"followers"`
}

// Authors lists everyone with published cards, optionally only those with cards
// in topic or whose name contains q, ordered by name.
func (s *Store) Authors(ctx context.Context, topic, q string, offset, limit int) ([]AuthorSummary, error) {
	rows, err := s.DB.Query(ctx, `SELECT a.name, count(DISTINCT s.id), count(c.id), array_agg(DISTINCT c.topic ORDER BY c.topic),
			(SELECT count(*) FROM follows f WHERE f.kind = 'author' AND f.target = a.name),
			array_agg(DISTINCT s.id)
		FROM sources s CROSS JOIN LATERAL unnest(s.authors) AS a(name)
		JOIN cards c ON c.source_id = s.id AND c.status = 'published'
		WHERE $4 = '' OR strpos(lower(a.name), lower($4)) > 0
		GROUP BY a.name
		HAVING $1 = '' OR bool_or(c.topic = $1)
		ORDER BY lower(a.name) OFFSET $2 LIMIT $3`, topic, offset, limit, q)
	if err != nil {
		return nil, err
	}
	videos := videoCounts()
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (AuthorSummary, error) {
		var x AuthorSummary
		var sources []string
		err := r.Scan(&x.Name, &x.Sources, &x.CardCount, &x.Topics, &x.Followers, &sources)
		for _, id := range sources {
			x.VideoCount += videos[id]
		}
		return x, err
	})
}
