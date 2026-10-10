package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Comment is a comment on a post. Replies point at a top-level comment.
type Comment struct {
	ID        string    `json:"id"`
	PostID    string    `json:"post_id"`
	ParentID  *string   `json:"parent_id"`
	Body      string    `json:"body"`
	Author    Profile   `json:"author"`
	CreatedAt time.Time `json:"created_at"`
}

// ReportsToHide is how many reports hide a comment until a moderator looks.
const ReportsToHide = 3

const commentCols = `cm.id::text, cm.card_id, cm.parent_id::text, cm.body, u.id::text, u.handle, u.display_name, cm.created_at`

func scanComment(r pgx.CollectableRow) (Comment, error) {
	var c Comment
	err := r.Scan(&c.ID, &c.PostID, &c.ParentID, &c.Body, &c.Author.ID, &c.Author.Handle, &c.Author.DisplayName, &c.CreatedAt)
	return c, err
}

// Comments lists a post's visible comments, oldest first, leaving out people
// the viewer blocked or muted and people who blocked the viewer.
func (s *Store) Comments(ctx context.Context, cardID, viewerID string, offset, limit int) ([]Comment, error) {
	if err := s.postExists(ctx, cardID); err != nil {
		return nil, err
	}
	rows, err := s.DB.Query(ctx, `SELECT `+commentCols+` FROM comments cm JOIN users u ON u.id = cm.user_id
		WHERE cm.card_id = $1 AND cm.status = 'visible' AND ($4::text IS NULL OR NOT `+hiddenFor("cm.user_id", "$4")+`)
		ORDER BY cm.created_at, cm.id OFFSET $2 LIMIT $3`, cardID, offset, limit, nullable(viewerID))
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, scanComment)
}

// ErrBlocked means the other person blocked the user.
var ErrBlocked = errors.New("blocked")

// AddComment adds a comment. A reply to a reply is attached to the top-level
// comment, so threads stay one level deep. It also returns the author of the
// comment replied to ("" for a top-level comment).
func (s *Store) AddComment(ctx context.Context, userID, cardID string, parentID *string, body string) (Comment, string, error) {
	if err := s.postExists(ctx, cardID); err != nil {
		return Comment{}, "", err
	}
	var repliedTo string
	if parentID != nil {
		var root string
		err := s.DB.QueryRow(ctx, `SELECT coalesce(parent_id, id)::text, user_id::text FROM comments
			WHERE id::text = $1 AND card_id = $2 AND status = 'visible'`, *parentID, cardID).Scan(&root, &repliedTo)
		if err != nil {
			return Comment{}, "", notFound(err)
		}
		if blocked, err := s.isBlockedBy(ctx, repliedTo, userID); err != nil || blocked {
			if err == nil {
				err = ErrBlocked
			}
			return Comment{}, "", err
		}
		parentID = &root
	}
	rows, err := s.DB.Query(ctx, `WITH cm AS (
			INSERT INTO comments (card_id, user_id, parent_id, body) VALUES ($1, $2, $3::uuid, $4) RETURNING *
		) SELECT `+commentCols+` FROM cm JOIN users u ON u.id = cm.user_id`, cardID, userID, parentID, body)
	if err != nil {
		return Comment{}, "", err
	}
	c, err := pgx.CollectExactlyOneRow(rows, scanComment)
	return c, repliedTo, err
}

// DeleteComment removes a comment written by the user, or any comment when moderator is set.
func (s *Store) DeleteComment(ctx context.Context, userID, id string, moderator bool) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM comments WHERE id::text = $1 AND (user_id = $2 OR $3)`, id, userID, moderator)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ReportComment records a report and hides the comment once enough people report it.
func (s *Store) ReportComment(ctx context.Context, userID, id, reason string) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `INSERT INTO comment_reports (comment_id, user_id, reason)
			SELECT id, $2, $3 FROM comments WHERE id::text = $1 ON CONFLICT DO NOTHING`, id, userID, reason)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			var ok bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM comments WHERE id::text = $1)`, id).Scan(&ok); err != nil {
				return err
			}
			if !ok {
				return ErrNotFound
			}
			return nil
		}
		_, err = tx.Exec(ctx, `UPDATE comments SET status = 'hidden' WHERE id::text = $1
			AND (SELECT count(*) FROM comment_reports WHERE comment_id::text = $1) >= $2`, id, ReportsToHide)
		return err
	})
}

// ReportedComment is a comment in the moderation queue.
type ReportedComment struct {
	Comment
	Status  string   `json:"status"`
	Reports int      `json:"reports"`
	Reasons []string `json:"reasons"`
}

// ReportedComments lists comments with reports that a moderator has not cleared, most reported first.
func (s *Store) ReportedComments(ctx context.Context) ([]ReportedComment, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+commentCols+`, cm.status, count(r.user_id), array_remove(array_agg(r.reason), '')
		FROM comments cm JOIN users u ON u.id = cm.user_id JOIN comment_reports r ON r.comment_id = cm.id
		GROUP BY cm.id, u.id ORDER BY count(r.user_id) DESC, cm.created_at LIMIT 200`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (ReportedComment, error) {
		var c ReportedComment
		err := r.Scan(&c.ID, &c.PostID, &c.ParentID, &c.Body, &c.Author.ID, &c.Author.Handle, &c.Author.DisplayName, &c.CreatedAt,
			&c.Status, &c.Reports, &c.Reasons)
		return c, err
	})
}

// ModerateComment hides a comment or restores it; either way its reports are cleared.
func (s *Store) ModerateComment(ctx context.Context, id string, hide bool) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		status := "visible"
		if hide {
			status = "hidden"
		}
		tag, err := tx.Exec(ctx, `UPDATE comments SET status = $2 WHERE id::text = $1`, id, status)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		_, err = tx.Exec(ctx, `DELETE FROM comment_reports WHERE comment_id::text = $1`, id)
		return err
	})
}
