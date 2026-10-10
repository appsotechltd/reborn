package store

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// Blocked is someone the user blocked or muted.
type Blocked struct {
	Profile
	Kind string `json:"kind"` // block or mute
}

// SetBlock blocks or mutes another user, or clears it when kind is "".
// Blocking also removes follows in both directions.
func (s *Store) SetBlock(ctx context.Context, userID, otherID, kind string) error {
	if userID == otherID {
		return ErrConflict
	}
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		if kind == "" {
			_, err := tx.Exec(ctx, `DELETE FROM blocks WHERE user_id = $1 AND blocked_id::text = $2`, userID, otherID)
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO blocks (user_id, blocked_id, kind) SELECT $1, id, $3 FROM users WHERE id::text = $2
			ON CONFLICT (user_id, blocked_id) DO UPDATE SET kind = EXCLUDED.kind`, userID, otherID, kind)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		if kind == "block" {
			_, err = tx.Exec(ctx, `DELETE FROM follows WHERE kind = 'user' AND
				((follower_id = $1 AND target = $2) OR (follower_id::text = $2 AND target = $1::text))`, userID, otherID)
		}
		return err
	})
}

// Blocks lists who the user blocked or muted.
func (s *Store) Blocks(ctx context.Context, userID string) ([]Blocked, error) {
	rows, err := s.DB.Query(ctx, `SELECT u.id::text, u.handle, u.display_name, b.kind FROM blocks b
		JOIN users u ON u.id = b.blocked_id WHERE b.user_id = $1 ORDER BY b.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Blocked, error) {
		var b Blocked
		err := r.Scan(&b.ID, &b.Handle, &b.DisplayName, &b.Kind)
		return b, err
	})
}

// isBlockedBy reports whether owner blocked other (mutes don't count).
func (s *Store) isBlockedBy(ctx context.Context, ownerID, otherID string) (bool, error) {
	var b bool
	err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM blocks WHERE user_id::text = $1 AND blocked_id::text = $2 AND kind = 'block')`,
		ownerID, otherID).Scan(&b)
	return b, err
}

// hiddenFor is a SQL condition that is true when the row's author (column col)
// was blocked or muted by viewer $n, or blocked the viewer.
func hiddenFor(col, viewerParam string) string {
	return `EXISTS (SELECT 1 FROM blocks bk WHERE (bk.user_id = ` + viewerParam + `::uuid AND bk.blocked_id = ` + col + `)
		OR (bk.kind = 'block' AND bk.user_id = ` + col + ` AND bk.blocked_id = ` + viewerParam + `::uuid))`
}
