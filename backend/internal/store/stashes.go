package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/srs"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// Stash is a user's named collection of cards ("Collections" in the apps).
type Stash struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CardCount   int       `json:"card_count"`
	IsPublic    bool      `json:"is_public"`
	CreatedAt   time.Time `json:"created_at"`
}

const stashSelect = `SELECT s.id::text, s.name, s.description, (SELECT count(*) FROM stash_cards sc WHERE sc.stash_id = s.id),
	s.is_public, s.created_at FROM stashes s `

func scanStash(row pgx.Row, extra ...any) (Stash, error) {
	var st Stash
	err := row.Scan(append([]any{&st.ID, &st.Name, &st.Description, &st.CardCount, &st.IsPublic, &st.CreatedAt}, extra...)...)
	return st, err
}

func conflictOr(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return ErrConflict
	}
	return notFound(err)
}

// Stashes lists a user's stashes, newest first.
func (s *Store) Stashes(ctx context.Context, userID string) ([]Stash, error) {
	rows, err := s.DB.Query(ctx, stashSelect+`WHERE s.user_id = $1 ORDER BY s.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Stash{}
	for rows.Next() {
		st, err := scanStash(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, st)
	}
	return out, rows.Err()
}

// CreateStash makes a stash; ErrConflict means the name is taken.
func (s *Store) CreateStash(ctx context.Context, userID, name, desc string) (Stash, error) {
	var id string
	if err := s.DB.QueryRow(ctx, `INSERT INTO stashes (user_id, name, description) VALUES ($1, $2, $3) RETURNING id::text`,
		userID, name, desc).Scan(&id); err != nil {
		return Stash{}, conflictOr(err)
	}
	return s.GetStash(ctx, userID, id)
}

// GetStash returns one of the user's stashes.
func (s *Store) GetStash(ctx context.Context, userID, id string) (Stash, error) {
	st, err := scanStash(s.DB.QueryRow(ctx, stashSelect+`WHERE s.id::text = $1 AND s.user_id = $2`, id, userID))
	return st, notFound(err)
}

// UpdateStash renames, re-describes, or publishes/unpublishes a stash.
func (s *Store) UpdateStash(ctx context.Context, userID, id string, name, desc *string, public *bool) (Stash, error) {
	tag, err := s.DB.Exec(ctx, `UPDATE stashes SET name = coalesce($3, name), description = coalesce($4, description),
		is_public = coalesce($5, is_public) WHERE id::text = $1 AND user_id = $2`, id, userID, name, desc, public)
	if err != nil {
		return Stash{}, conflictOr(err)
	}
	if tag.RowsAffected() == 0 {
		return Stash{}, ErrNotFound
	}
	return s.GetStash(ctx, userID, id)
}

// DeleteStash removes a stash (its review schedule is kept).
func (s *Store) DeleteStash(ctx context.Context, userID, id string) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM stashes WHERE id::text = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// StashCards returns the cards in a stash, most recently added first.
func (s *Store) StashCards(ctx context.Context, userID, id string) ([]Card, error) {
	if _, err := s.GetStash(ctx, userID, id); err != nil {
		return nil, err
	}
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`JOIN stash_cards sc ON sc.card_id = c.id
		WHERE sc.stash_id::text = $1 AND ((c.status = 'published' AND `+visibleTo("$2")+`) OR (c.author_id = $2 AND c.status <> 'deleted'))
		ORDER BY sc.added_at DESC`, id, userID)
	if err != nil {
		return nil, err
	}
	return collectCards(rows)
}

// AddToStash puts a card in a stash and enrols it in review.
func (s *Store) AddToStash(ctx context.Context, userID, stashID, cardID string, now time.Time) error {
	return withTx(ctx, s.DB, func(tx pgx.Tx) error {
		var ok bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM stashes WHERE id::text = $1 AND user_id = $2)
			AND EXISTS (SELECT 1 FROM cards WHERE id = $3 AND (status = 'published' OR (author_id = $2 AND status <> 'deleted')))`,
			stashID, userID, cardID).Scan(&ok); err != nil {
			return err
		}
		if !ok {
			return ErrNotFound
		}
		if _, err := tx.Exec(ctx, `INSERT INTO stash_cards (stash_id, card_id) VALUES ($1::uuid, $2) ON CONFLICT DO NOTHING`, stashID, cardID); err != nil {
			return err
		}
		st := srs.New(now)
		_, err := tx.Exec(ctx, `INSERT INTO reviews (user_id, card_id, ease, due_at) VALUES ($1, $2, $3, $4)
			ON CONFLICT (user_id, card_id) DO NOTHING`, userID, cardID, st.Ease, st.DueAt)
		return err
	})
}

// RemoveFromStash takes a card out of a stash.
func (s *Store) RemoveFromStash(ctx context.Context, userID, stashID, cardID string) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM stash_cards sc USING stashes st
		WHERE sc.stash_id = st.id AND st.id::text = $1 AND st.user_id = $2 AND sc.card_id = $3`, stashID, userID, cardID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// PublicStash is a stash anyone can view, with its owner.
type PublicStash struct {
	Stash
	Owner Profile `json:"owner"`
}

// GetPublicStash returns a public stash and its cards.
func (s *Store) GetPublicStash(ctx context.Context, id string) (PublicStash, []Card, error) {
	var ps PublicStash
	q := strings.Replace(stashSelect, " FROM stashes s ", ", u.id::text, u.handle, u.display_name FROM stashes s JOIN users u ON u.id = s.user_id ", 1)
	st, err := scanStash(s.DB.QueryRow(ctx, q+`WHERE s.id::text = $1 AND s.is_public`, id), &ps.Owner.ID, &ps.Owner.Handle, &ps.Owner.DisplayName)
	if err != nil {
		return ps, nil, notFound(err)
	}
	ps.Stash = st
	rows, err := s.DB.Query(ctx, `SELECT `+cardCols+cardFrom+`JOIN stash_cards sc ON sc.card_id = c.id
		WHERE sc.stash_id::text = $1 AND c.status = 'published' AND `+everyoneOnly+` ORDER BY sc.added_at DESC`, id)
	if err != nil {
		return ps, nil, err
	}
	cards, err := collectCards(rows)
	return ps, cards, err
}

// PublicStashes lists a user's public stashes, newest first.
func (s *Store) PublicStashes(ctx context.Context, ownerID string) ([]Stash, error) {
	rows, err := s.DB.Query(ctx, stashSelect+`WHERE s.user_id::text = $1 AND s.is_public ORDER BY s.created_at DESC`, ownerID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Stash, error) { return scanStash(r) })
}
