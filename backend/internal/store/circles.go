package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Circle is a small group reading and discussing one book together.
type Circle struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Source      SourceRef `json:"source"`
	Owner       *Profile  `json:"owner"`
	Members     int       `json:"members"`
	IsMember    bool      `json:"is_member"`
	Role        *string   `json:"role"` // owner or member, when the viewer is in it
	CreatedAt   time.Time `json:"created_at"`
}

// MaxCircleMembers keeps circles small.
const MaxCircleMembers = 50

// ErrFull means a circle has no room.
var ErrFull = errors.New("circle is full")

// ErrWrongBook means an attached idea is not from the circle's book.
var ErrWrongBook = errors.New("idea is from another book")

const circleCols = `ci.id::text, ci.name, ci.description, ci.created_at,
	s.id, s.title, s.authors, s.kind, s.url, s.licence, s.licence_url, s.attribution,
	o.id::text, o.handle, o.display_name,
	(SELECT count(*) FROM circle_members m WHERE m.circle_id = ci.id),
	(SELECT role FROM circle_members m WHERE m.circle_id = ci.id AND m.user_id = $1::uuid)`

const circleFrom = ` FROM circles ci JOIN sources s ON s.id = ci.source_id LEFT JOIN users o ON o.id = ci.owner_id `

func scanCircle(r pgx.CollectableRow) (Circle, error) {
	var c Circle
	var oid, oh, on *string
	err := r.Scan(&c.ID, &c.Name, &c.Description, &c.CreatedAt,
		&c.Source.ID, &c.Source.Title, &c.Source.Authors, &c.Source.Kind, &c.Source.URL, &c.Source.Licence, &c.Source.LicenceURL, &c.Source.Attribution,
		&oid, &oh, &on, &c.Members, &c.Role)
	if oid != nil {
		c.Owner = &Profile{ID: *oid, Handle: *oh, DisplayName: *on}
	}
	c.IsMember = c.Role != nil
	return c, err
}

// Circles lists circles, optionally for one book or only those the viewer is in.
func (s *Store) Circles(ctx context.Context, viewerID, sourceID string, mine bool, limit int) ([]Circle, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+circleCols+circleFrom+`
		WHERE ($2 = '' OR ci.source_id = $2)
		  AND (NOT $3 OR EXISTS (SELECT 1 FROM circle_members m WHERE m.circle_id = ci.id AND m.user_id = $1::uuid))
		ORDER BY (SELECT count(*) FROM circle_members m WHERE m.circle_id = ci.id) DESC, ci.created_at DESC LIMIT $4`,
		nullable(viewerID), sourceID, mine, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, scanCircle)
}

// GetCircle returns one circle.
func (s *Store) GetCircle(ctx context.Context, viewerID, id string) (Circle, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+circleCols+circleFrom+`WHERE ci.id::text = $2`, nullable(viewerID), id)
	if err != nil {
		return Circle{}, err
	}
	c, err := pgx.CollectExactlyOneRow(rows, scanCircle)
	return c, notFound(err)
}

// CreateCircle makes a circle for a book with the user as owner.
func (s *Store) CreateCircle(ctx context.Context, userID, sourceID, name, desc string) (Circle, error) {
	var id string
	err := withTx(ctx, s.DB, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `INSERT INTO circles (name, description, source_id, owner_id)
			SELECT $1, $2, id, $4 FROM sources WHERE id = $3 RETURNING id::text`, name, desc, sourceID, userID).Scan(&id); err != nil {
			return notFound(err)
		}
		_, err := tx.Exec(ctx, `INSERT INTO circle_members (circle_id, user_id, role) VALUES ($1::uuid, $2, 'owner')`, id, userID)
		return err
	})
	if err != nil {
		return Circle{}, err
	}
	return s.GetCircle(ctx, userID, id)
}

// JoinCircle adds the user to a circle.
func (s *Store) JoinCircle(ctx context.Context, userID, id string) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var members int
		if err := tx.QueryRow(ctx, `SELECT (SELECT count(*) FROM circle_members WHERE circle_id = ci.id)
			FROM circles ci WHERE ci.id::text = $1 FOR UPDATE`, id).Scan(&members); err != nil {
			return notFound(err)
		}
		if members >= MaxCircleMembers {
			return ErrFull
		}
		_, err := tx.Exec(ctx, `INSERT INTO circle_members (circle_id, user_id) VALUES ($1::uuid, $2) ON CONFLICT DO NOTHING`, id, userID)
		return err
	})
}

// LeaveCircle removes the user. When the owner leaves, the longest-standing member takes over;
// a circle nobody is in is deleted.
func (s *Store) LeaveCircle(ctx context.Context, userID, id string) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM circle_members WHERE circle_id::text = $1 AND user_id = $2`, id, userID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		var next *string
		if err := tx.QueryRow(ctx, `SELECT user_id::text FROM circle_members WHERE circle_id::text = $1 ORDER BY joined_at LIMIT 1`, id).Scan(&next); err != nil && err != pgx.ErrNoRows {
			return err
		}
		if next == nil {
			_, err = tx.Exec(ctx, `DELETE FROM circles WHERE id::text = $1`, id)
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE circles SET owner_id = $2::uuid WHERE id::text = $1 AND (owner_id = $3 OR owner_id IS NULL)`, id, *next, userID); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE circle_members m SET role = 'owner' FROM circles c
			WHERE c.id = m.circle_id AND c.id::text = $1 AND m.user_id = c.owner_id`, id)
		return err
	})
}

// CircleMessage is a message in a circle's discussion.
type CircleMessage struct {
	ID        string    `json:"id"`
	CircleID  string    `json:"circle_id"`
	Body      string    `json:"body"`
	PostID    *string   `json:"post_id"` // an idea from the book being discussed
	Author    Profile   `json:"author"`
	CreatedAt time.Time `json:"created_at"`
}

const circleMsgCols = `cm.id::text, cm.circle_id::text, cm.body, cm.card_id, u.id::text, u.handle, u.display_name, cm.created_at`

func scanCircleMessage(r pgx.CollectableRow) (CircleMessage, error) {
	var m CircleMessage
	err := r.Scan(&m.ID, &m.CircleID, &m.Body, &m.PostID, &m.Author.ID, &m.Author.Handle, &m.Author.DisplayName, &m.CreatedAt)
	return m, err
}

// isCircleMember reports whether the user is in the circle.
func (s *Store) isCircleMember(ctx context.Context, userID, id string) (bool, error) {
	var ok bool
	err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM circle_members WHERE circle_id::text = $1 AND user_id::text = $2)`, id, userID).Scan(&ok)
	return ok, err
}

// CircleMessages lists a circle's discussion for a member, newest last. before pages backwards.
func (s *Store) CircleMessages(ctx context.Context, userID, id string, before *time.Time, limit int) ([]CircleMessage, error) {
	if ok, err := s.isCircleMember(ctx, userID, id); err != nil || !ok {
		if err == nil {
			err = ErrNotFound
		}
		return nil, err
	}
	rows, err := s.DB.Query(ctx, `SELECT * FROM (SELECT `+circleMsgCols+` FROM circle_messages cm JOIN users u ON u.id = cm.user_id
		WHERE cm.circle_id::text = $1 AND ($2::timestamptz IS NULL OR cm.created_at < $2) AND NOT `+hiddenFor("cm.user_id", "$4")+`
		ORDER BY cm.created_at DESC LIMIT $3) x ORDER BY 8`, id, before, limit, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, scanCircleMessage)
}

// AddCircleMessage posts to a circle's discussion. postID, when set, must be from the circle's book.
func (s *Store) AddCircleMessage(ctx context.Context, userID, id, body, postID string) (CircleMessage, []string, error) {
	if ok, err := s.isCircleMember(ctx, userID, id); err != nil || !ok {
		if err == nil {
			err = ErrNotFound
		}
		return CircleMessage{}, nil, err
	}
	if postID != "" {
		var ok bool
		if err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM cards c JOIN circles ci ON ci.source_id = c.source_id
			WHERE ci.id::text = $1 AND c.id = $2 AND c.status = 'published')`, id, postID).Scan(&ok); err != nil {
			return CircleMessage{}, nil, err
		}
		if !ok {
			return CircleMessage{}, nil, ErrWrongBook
		}
	}
	rows, err := s.DB.Query(ctx, `WITH cm AS (
			INSERT INTO circle_messages (circle_id, user_id, body, card_id) VALUES ($1::uuid, $2, $3, $4) RETURNING *
		) SELECT `+circleMsgCols+` FROM cm JOIN users u ON u.id = cm.user_id`, id, userID, body, nullable(postID))
	if err != nil {
		return CircleMessage{}, nil, err
	}
	m, err := pgx.CollectExactlyOneRow(rows, scanCircleMessage)
	if err != nil {
		return m, nil, err
	}
	others, err := s.DB.Query(ctx, `SELECT user_id::text FROM circle_members WHERE circle_id::text = $1 AND user_id <> $2`, id, userID)
	if err != nil {
		return m, nil, err
	}
	ids, err := pgx.CollectRows(others, pgx.RowTo[string])
	return m, ids, err
}

// DeleteCircleMessage removes a message by its author, the circle owner or a moderator.
func (s *Store) DeleteCircleMessage(ctx context.Context, userID, circleID, msgID string, moderator bool) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM circle_messages cm USING circles ci
		WHERE cm.circle_id = ci.id AND ci.id::text = $1 AND cm.id::text = $2
		  AND (cm.user_id = $3 OR ci.owner_id = $3 OR $4)`, circleID, msgID, userID, moderator)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// CircleMember is someone in a circle.
type CircleMember struct {
	Profile
	Role     string    `json:"role"`
	JoinedAt time.Time `json:"joined_at"`
}

// CircleMembers lists a circle's members, owner first, leaving out people the
// viewer blocked or muted and people who blocked them.
func (s *Store) CircleMembers(ctx context.Context, viewerID, id string) ([]CircleMember, error) {
	if _, err := s.GetCircle(ctx, viewerID, id); err != nil {
		return nil, err
	}
	rows, err := s.DB.Query(ctx, `SELECT u.id::text, u.handle, u.display_name, m.role, m.joined_at
		FROM circle_members m JOIN users u ON u.id = m.user_id
		WHERE m.circle_id::text = $1 AND NOT `+hiddenFor("m.user_id", "NULLIF($2, '')")+`
		ORDER BY m.role = 'owner' DESC, m.joined_at`, id, viewerID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (CircleMember, error) {
		var m CircleMember
		err := row.Scan(&m.ID, &m.Handle, &m.DisplayName, &m.Role, &m.JoinedAt)
		return m, err
	})
}
