// Package cache wraps Redis for small caches and rate limits. Every method
// degrades gracefully: when Redis is down, caches miss and limits allow.
package cache

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
)

// Cache is a thin Redis wrapper.
type Cache struct {
	R *redis.Client
}

// Open connects to Redis at url.
func Open(ctx context.Context, url string) (*Cache, error) {
	opt, err := redis.ParseURL(url)
	if err != nil {
		return nil, err
	}
	c := redis.NewClient(opt)
	if err := c.Ping(ctx).Err(); err != nil {
		_ = c.Close()
		return nil, err
	}
	return &Cache{R: c}, nil
}

// GetJSON loads key into v and reports whether it was found.
func (c *Cache) GetJSON(ctx context.Context, key string, v any) bool {
	if c == nil {
		return false
	}
	b, err := c.R.Get(ctx, key).Bytes()
	if err != nil {
		if err != redis.Nil {
			slog.Warn("cache get", "key", key, "err", err)
		}
		return false
	}
	return json.Unmarshal(b, v) == nil
}

// SetJSON stores v under key for ttl.
func (c *Cache) SetJSON(ctx context.Context, key string, v any, ttl time.Duration) {
	if c == nil {
		return
	}
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	if err := c.R.Set(ctx, key, b, ttl).Err(); err != nil {
		slog.Warn("cache set", "key", key, "err", err)
	}
}

// Delete removes keys.
func (c *Cache) Delete(ctx context.Context, keys ...string) {
	if c == nil || len(keys) == 0 {
		return
	}
	_ = c.R.Del(ctx, keys...).Err()
}

// Allow counts a hit against key in a fixed window and reports whether the
// count is still within limit.
func (c *Cache) Allow(ctx context.Context, key string, limit int, window time.Duration) bool {
	if c == nil || limit <= 0 {
		return true
	}
	pipe := c.R.TxPipeline()
	incr := pipe.Incr(ctx, key)
	pipe.ExpireNX(ctx, key, window)
	if _, err := pipe.Exec(ctx); err != nil {
		slog.Warn("rate limit", "key", key, "err", err)
		return true
	}
	return incr.Val() <= int64(limit)
}
