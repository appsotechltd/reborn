// Package store holds every Postgres query the API uses.
package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a row does not exist or is not visible to the caller.
var ErrNotFound = errors.New("not found")

// ErrConflict is returned on a unique-constraint violation.
var ErrConflict = errors.New("conflict")

// Store wraps the connection pool.
type Store struct {
	DB *pgxpool.Pool
}

// New returns a Store over pool.
func New(pool *pgxpool.Pool) *Store { return &Store{DB: pool} }

func notFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

func withTx(ctx context.Context, pool *pgxpool.Pool, fn func(pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}
