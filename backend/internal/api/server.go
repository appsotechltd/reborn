// Package api serves the Reborn HTTP API described in docs/API.md.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/agent"
	"github.com/appsotechltd/reborn/backend/internal/auth"
	"github.com/appsotechltd/reborn/backend/internal/cache"
	"github.com/appsotechltd/reborn/backend/internal/embed"
	"github.com/appsotechltd/reborn/backend/internal/explainers"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Chatter answers agent questions; *agent.Agent implements it.
type Chatter interface {
	Chat(ctx context.Context, history []agent.Message) (agent.Reply, error)
}

// Server holds the API's dependencies.
type Server struct {
	Store       *store.Store
	Cache       *cache.Cache // may be nil
	Tokens      *auth.Tokens
	Agent       Chatter        // nil when no Anthropic key is configured
	Embedder    embed.Embedder // nil when no embedding key is configured
	AgentHourly int
	CORSOrigins string
	// ExplainerDir holds rendered explainer videos served under /media/explainers/; empty disables the route.
	ExplainerDir string
	Now          func() time.Time
}

// Handler returns the routed, middleware-wrapped handler.
func (s *Server) Handler() http.Handler {
	if s.Now == nil {
		s.Now = time.Now
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	if s.ExplainerDir != "" {
		mux.Handle("GET "+explainers.Route, explainers.Handler(s.ExplainerDir))
	}

	mux.HandleFunc("GET /v1/topics", s.topics)
	mux.HandleFunc("GET /v1/feed", s.feed)
	mux.HandleFunc("GET /v1/daily", s.daily)
	mux.HandleFunc("GET /v1/cards", s.cardsByIDs)
	mux.HandleFunc("GET /v1/cards/{id}", s.card)
	mux.HandleFunc("POST /v1/cards/{id}/view", s.authed(s.view))
	mux.HandleFunc("GET /v1/sources", s.sources)
	mux.HandleFunc("GET /v1/sources/{id}", s.source)
	mux.HandleFunc("GET /v1/sitemap", s.sitemap)
	mux.HandleFunc("GET /v1/search", s.search)

	mux.HandleFunc("POST /v1/auth/register", s.register)
	mux.HandleFunc("POST /v1/auth/login", s.login)
	mux.HandleFunc("GET /v1/me", s.authed(s.me))
	mux.HandleFunc("PATCH /v1/me", s.authed(s.updateMe))

	mux.HandleFunc("GET /v1/stashes", s.authed(s.listStashes))
	mux.HandleFunc("POST /v1/stashes", s.authed(s.createStash))
	mux.HandleFunc("GET /v1/stashes/{id}", s.authed(s.getStash))
	mux.HandleFunc("PATCH /v1/stashes/{id}", s.authed(s.updateStash))
	mux.HandleFunc("DELETE /v1/stashes/{id}", s.authed(s.deleteStash))
	mux.HandleFunc("PUT /v1/stashes/{id}/cards/{cardId}", s.authed(s.addToStash))
	mux.HandleFunc("DELETE /v1/stashes/{id}/cards/{cardId}", s.authed(s.removeFromStash))

	mux.HandleFunc("GET /v1/review/due", s.authed(s.dueReviews))
	mux.HandleFunc("POST /v1/review/{cardId}", s.authed(s.grade))
	mux.HandleFunc("GET /v1/quiz", s.authed(s.quiz))

	mux.HandleFunc("POST /v1/contributions", s.authed(s.contribute))
	mux.HandleFunc("GET /v1/contributions/mine", s.authed(s.myContributions))
	mux.HandleFunc("GET /v1/moderation/queue", s.moderator(s.queue))
	mux.HandleFunc("POST /v1/moderation/{id}/approve", s.moderator(s.approve))
	mux.HandleFunc("POST /v1/moderation/{id}/reject", s.moderator(s.reject))

	mux.HandleFunc("POST /v1/agent/chat", s.authed(s.chat))

	return s.recoverer(s.logger(s.cors(s.identify(mux))))
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DB.Ping(r.Context()); err != nil {
		writeError(w, http.StatusServiceUnavailable, "db_unavailable", "database is unreachable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// --- helpers ---

type ctxKey int

const userKey ctxKey = 0

// userID returns the signed-in user's id, or "".
func userID(r *http.Request) string {
	id, _ := r.Context().Value(userKey).(string)
	return id
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": msg}})
}

func (s *Server) fail(w http.ResponseWriter, r *http.Request, err error, what string) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", what+" not found")
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, "conflict", what+" conflicts with an existing one")
	case errors.Is(err, context.Canceled):
		// client went away
	default:
		slog.Error("request failed", "path", r.URL.Path, "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "something went wrong")
	}
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid JSON body: "+err.Error())
		return false
	}
	return true
}

func splitList(s string) []string {
	out := []string{}
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// --- middleware ---

func (s *Server) identify(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := r.Header.Get("Authorization")
		if tok, ok := strings.CutPrefix(h, "Bearer "); ok {
			id, err := s.Tokens.Verify(strings.TrimSpace(tok))
			if err != nil {
				writeError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}
			r = r.WithContext(context.WithValue(r.Context(), userKey, id))
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) authed(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if userID(r) == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized", "sign in required")
			return
		}
		h(w, r)
	}
}

func (s *Server) moderator(h http.HandlerFunc) http.HandlerFunc {
	return s.authed(func(w http.ResponseWriter, r *http.Request) {
		u, err := s.Store.UserByID(r.Context(), userID(r))
		if err != nil {
			s.fail(w, r, err, "user")
			return
		}
		if u.Role != "moderator" {
			writeError(w, http.StatusForbidden, "forbidden", "moderators only")
			return
		}
		h(w, r)
	})
}

func (s *Server) cors(next http.Handler) http.Handler {
	allowed := splitList(s.CORSOrigins)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			for _, a := range allowed {
				if a == "*" || a == origin {
					w.Header().Set("Access-Control-Allow-Origin", origin)
					w.Header().Set("Vary", "Origin")
					w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
					w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
					w.Header().Set("Access-Control-Max-Age", "600")
					break
				}
			}
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *Server) logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		slog.Info("http", "method", r.Method, "path", r.URL.Path, "status", rec.status, "ms", time.Since(start).Milliseconds())
	})
}

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				slog.Error("panic", "path", r.URL.Path, "panic", v)
				writeError(w, http.StatusInternalServerError, "internal", "something went wrong")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
