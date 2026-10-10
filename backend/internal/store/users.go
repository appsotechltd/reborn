package store

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

// User is the API shape of an account.
type User struct {
	ID          string   `json:"id"`
	Email       string   `json:"email"`
	DisplayName string   `json:"display_name"`
	Role        string   `json:"role"`
	Topics      []string `json:"topics"`
}

const userCols = `id::text, email, display_name, role, topics`

// CreateUser inserts a user; ErrConflict means the email is taken.
func (s *Store) CreateUser(ctx context.Context, email, hash, name string) (User, error) {
	var u User
	err := s.DB.QueryRow(ctx, `INSERT INTO users (email, password_hash, display_name) VALUES ($1, $2, $3)
		RETURNING `+userCols, strings.ToLower(strings.TrimSpace(email)), hash, name).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.Role, &u.Topics)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return u, ErrConflict
	}
	return u, err
}

// UserByEmail returns a user and their password hash.
func (s *Store) UserByEmail(ctx context.Context, email string) (User, string, error) {
	var u User
	var hash string
	err := s.DB.QueryRow(ctx, `SELECT `+userCols+`, password_hash FROM users WHERE email = $1`,
		strings.ToLower(strings.TrimSpace(email))).Scan(&u.ID, &u.Email, &u.DisplayName, &u.Role, &u.Topics, &hash)
	return u, hash, notFound(err)
}

// UserByID returns a user.
func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	var u User
	err := s.DB.QueryRow(ctx, `SELECT `+userCols+` FROM users WHERE id = $1`, id).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.Role, &u.Topics)
	return u, notFound(err)
}

// UpdateUser changes the display name and/or topics (nil leaves a field as is).
func (s *Store) UpdateUser(ctx context.Context, id string, name *string, topics []string) (User, error) {
	var u User
	err := s.DB.QueryRow(ctx, `UPDATE users SET display_name = coalesce($2, display_name), topics = coalesce($3, topics)
		WHERE id = $1 RETURNING `+userCols, id, name, topics).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.Role, &u.Topics)
	return u, notFound(err)
}

// SetRole changes a user's role by email.
func (s *Store) SetRole(ctx context.Context, email, role string) error {
	tag, err := s.DB.Exec(ctx, `UPDATE users SET role = $2 WHERE email = $1`, strings.ToLower(strings.TrimSpace(email)), role)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
