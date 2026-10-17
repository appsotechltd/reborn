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
	"github.com/appsotechltd/reborn/backend/internal/mail"
	"github.com/appsotechltd/reborn/backend/internal/objstore"
	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/push"
	"github.com/appsotechltd/reborn/backend/internal/rebornai"
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
	Now         func() time.Time

	WebBaseURL string      // the web app, for reset links and gift return pages
	Mailer     mail.Sender // nil drops emails
	Stripe     *payments.Stripe
	Apple      *payments.Apple
	Google     *payments.Google

	StripePrices    map[string]string // premium plan id -> Stripe price id
	GoogleRTDNToken string            // shared secret in the Play notifications push URL
	Push            push.Sender       // nil disables push notifications

	// AI is Reborn AI, the premium assistant; nil when no OpenAI key is configured.
	AI             *rebornai.Assistant
	AIMonthlyUnits int // AI units premium includes each month
	AIHourly       int // messages a member may send Reborn AI per hour

	// Gifts on member cards are shared with the writer: GiftCommission percent
	// of what is left after the payment fee stays with Reborn. StoreFee is the
	// percent Apple and Google keep.
	GiftCommission int
	StoreFee       int

	// Media stores videos, images and other files: R2 in production, a local
	// folder in development, which the API then serves under /media/.
	Media objstore.Store
	// MediaClient fetches media files the API passes on (card videos to share); nil uses the default.
	MediaClient *http.Client
}

func (s *Server) mediaClient() *http.Client {
	if s.MediaClient != nil {
		return s.MediaClient
	}
	return http.DefaultClient
}

// Handler returns the routed, middleware-wrapped handler.
func (s *Server) Handler() http.Handler {
	if s.Now == nil {
		s.Now = time.Now
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	if local, ok := s.Media.(*objstore.Local); ok {
		mux.Handle("GET /media/", local.Handler("/media/"))
	}

	mux.HandleFunc("GET /v1/topics", s.topics)
	mux.HandleFunc("GET /v1/feed", s.feed)
	mux.HandleFunc("GET /v1/daily", s.daily)
	mux.HandleFunc("GET /v1/cards", s.cardsByIDs)
	mux.HandleFunc("GET /v1/cards/{id}", s.card)
	mux.HandleFunc("POST /v1/cards/{id}/view", s.authed(s.view))
	mux.HandleFunc("GET /v1/cards/{id}/video", s.cardVideo)
	mux.HandleFunc("GET /v1/cards/{id}/picture", s.cardPicture)
	mux.HandleFunc("GET /v1/sources", s.sources)
	mux.HandleFunc("GET /v1/sources/{id}", s.source)
	mux.HandleFunc("GET /v1/sitemap", s.sitemap)
	mux.HandleFunc("GET /v1/search", s.search)
	mux.HandleFunc("GET /v1/summaries", s.summaries)
	mux.HandleFunc("GET /v1/summaries/{id}", s.summary)
	mux.HandleFunc("PUT /v1/summaries/{id}/progress", s.authed(s.summaryProgress))
	mux.HandleFunc("GET /v1/subjects", s.subjects)
	mux.HandleFunc("GET /v1/subjects/{id}", s.subject)

	mux.HandleFunc("POST /v1/auth/register", s.register)
	mux.HandleFunc("POST /v1/auth/login", s.login)
	mux.HandleFunc("POST /v1/auth/forgot", s.forgotPassword)
	mux.HandleFunc("POST /v1/auth/reset", s.resetPassword)
	mux.HandleFunc("GET /v1/me", s.authed(s.me))
	mux.HandleFunc("PATCH /v1/me", s.authed(s.updateMe))
	mux.HandleFunc("DELETE /v1/me", s.authed(s.deleteMe))
	mux.HandleFunc("GET /v1/me/favorites", s.authed(s.myFavorites))
	mux.HandleFunc("GET /v1/me/following", s.authed(s.myFollowing))
	mux.HandleFunc("GET /v1/me/streak", s.authed(s.streak))
	mux.HandleFunc("GET /v1/me/referrals", s.authed(s.referrals))
	mux.HandleFunc("GET /v1/me/blocks", s.authed(s.myBlocks))
	mux.HandleFunc("PUT /v1/blocks/{userId}", s.authed(s.setBlock))
	mux.HandleFunc("DELETE /v1/blocks/{userId}", s.authed(s.clearBlock))

	mux.HandleFunc("GET /v1/notifications", s.authed(s.notifications))
	mux.HandleFunc("POST /v1/notifications/read", s.authed(s.readNotifications))
	mux.HandleFunc("POST /v1/devices", s.authed(s.registerDevice))
	mux.HandleFunc("DELETE /v1/devices/{token}", s.authed(s.removeDevice))

	mux.HandleFunc("GET /v1/trending", s.trending)
	mux.HandleFunc("GET /v1/discover", s.discover)
	mux.HandleFunc("GET /v1/public/stashes/{id}", s.publicStash)
	mux.HandleFunc("GET /v1/users/{handle}/stashes", s.profileStashes)

	mux.HandleFunc("GET /v1/circles", s.circles)
	mux.HandleFunc("POST /v1/circles", s.authed(s.createCircle))
	mux.HandleFunc("GET /v1/circles/{id}", s.circle)
	mux.HandleFunc("GET /v1/circles/{id}/members", s.circleMembers)
	mux.HandleFunc("POST /v1/circles/{id}/join", s.authed(s.joinCircle))
	mux.HandleFunc("POST /v1/circles/{id}/leave", s.authed(s.leaveCircle))
	mux.HandleFunc("GET /v1/circles/{id}/messages", s.authed(s.circleMessages))
	mux.HandleFunc("POST /v1/circles/{id}/messages", s.authed(s.addCircleMessage))
	mux.HandleFunc("DELETE /v1/circles/{id}/messages/{msgId}", s.authed(s.deleteCircleMessage))

	mux.HandleFunc("GET /v1/premium", s.premium)
	mux.HandleFunc("POST /v1/premium/checkout", s.authed(s.premiumCheckout))
	mux.HandleFunc("POST /v1/premium/portal", s.authed(s.premiumPortal))
	mux.HandleFunc("POST /v1/premium/apple", s.authed(s.premiumApple))
	mux.HandleFunc("POST /v1/premium/google", s.authed(s.premiumGoogle))
	mux.HandleFunc("POST /v1/webhooks/apple", s.appleWebhook)
	mux.HandleFunc("POST /v1/webhooks/google", s.googleWebhook)
	mux.HandleFunc("GET /v1/admin/stats", s.moderator(s.adminStats))

	mux.HandleFunc("GET /v1/timeline", s.timeline)
	mux.HandleFunc("POST /v1/seen", s.authed(s.markSeen))
	mux.HandleFunc("GET /v1/posts/{id}", s.post)
	mux.HandleFunc("PUT /v1/posts/{id}/favorite", s.authed(s.setFavorite(true)))
	mux.HandleFunc("DELETE /v1/posts/{id}/favorite", s.authed(s.setFavorite(false)))
	mux.HandleFunc("PUT /v1/posts/{id}/reaction", s.authed(s.setReaction))
	mux.HandleFunc("DELETE /v1/posts/{id}/reaction", s.authed(s.clearReaction))
	mux.HandleFunc("POST /v1/posts/{id}/share", s.share)
	mux.HandleFunc("GET /v1/posts/{id}/comments", s.comments)
	mux.HandleFunc("POST /v1/posts/{id}/comments", s.authed(s.addComment))
	mux.HandleFunc("DELETE /v1/comments/{id}", s.authed(s.deleteComment))
	mux.HandleFunc("POST /v1/comments/{id}/report", s.authed(s.reportComment))

	mux.HandleFunc("PUT /v1/follows/{kind}/{target}", s.authed(s.setFollow(true)))
	mux.HandleFunc("DELETE /v1/follows/{kind}/{target}", s.authed(s.setFollow(false)))
	mux.HandleFunc("GET /v1/users/{handle}", s.profile)
	mux.HandleFunc("GET /v1/users/{handle}/favorites", s.profileFavorites)
	mux.HandleFunc("GET /v1/users/{handle}/followers", s.profileFollowers)
	mux.HandleFunc("GET /v1/authors", s.authors)
	mux.HandleFunc("GET /v1/authors/{name}", s.author)

	mux.HandleFunc("GET /v1/gifts/tiers", s.giftTiers)
	mux.HandleFunc("GET /v1/gifts/{id}", s.authed(s.gift))
	mux.HandleFunc("POST /v1/posts/{id}/gifts/checkout", s.authed(s.giftCheckout))
	mux.HandleFunc("POST /v1/posts/{id}/gifts/apple", s.authed(s.giftApple))
	mux.HandleFunc("POST /v1/posts/{id}/gifts/google", s.authed(s.giftGoogle))
	mux.HandleFunc("POST /v1/webhooks/stripe", s.stripeWebhook)

	mux.HandleFunc("GET /v1/stashes", s.authed(s.listStashes))
	mux.HandleFunc("POST /v1/stashes", s.authed(s.createStash))
	mux.HandleFunc("GET /v1/stashes/{id}", s.authed(s.getStash))
	mux.HandleFunc("PATCH /v1/stashes/{id}", s.authed(s.updateStash))
	mux.HandleFunc("DELETE /v1/stashes/{id}", s.authed(s.deleteStash))
	mux.HandleFunc("PUT /v1/stashes/{id}/cards/{cardId}", s.authed(s.addToStash))
	mux.HandleFunc("DELETE /v1/stashes/{id}/cards/{cardId}", s.authed(s.removeFromStash))

	mux.HandleFunc("GET /v1/studio", s.studio)
	mux.HandleFunc("GET /v1/me/categories", s.authed(s.myCategories))
	mux.HandleFunc("POST /v1/me/categories", s.authed(s.createCategory))
	mux.HandleFunc("PATCH /v1/me/categories/{id}", s.authed(s.renameCategory))
	mux.HandleFunc("DELETE /v1/me/categories/{id}", s.authed(s.deleteCategory))
	mux.HandleFunc("GET /v1/me/cards", s.authed(s.myCards))
	mux.HandleFunc("POST /v1/me/cards", s.authed(s.createMyCard))
	mux.HandleFunc("GET /v1/me/cards/{id}", s.authed(s.myCard))
	mux.HandleFunc("PATCH /v1/me/cards/{id}", s.authed(s.updateMyCard))
	mux.HandleFunc("DELETE /v1/me/cards/{id}", s.authed(s.deleteMyCard))
	mux.HandleFunc("POST /v1/me/cards/{id}/image", s.authed(s.makeCardImage))
	mux.HandleFunc("POST /v1/me/cards/{id}/audio", s.authed(s.makeCardAudio))
	mux.HandleFunc("POST /v1/me/cards/{id}/video", s.authed(s.makeCardVideo))
	mux.HandleFunc("DELETE /v1/me/cards/{id}/{kind}", s.authed(s.deleteCardMedia))
	mux.HandleFunc("GET /v1/me/earnings", s.authed(s.earnings))
	mux.HandleFunc("GET /v1/me/plan", s.authed(s.myPlan))
	mux.HandleFunc("PUT /v1/me/plan", s.authed(s.setMyPlan))
	mux.HandleFunc("GET /v1/me/subscriptions", s.authed(s.mySubscriptions))
	mux.HandleFunc("GET /v1/users/{handle}/plan", s.userPlan)
	mux.HandleFunc("POST /v1/users/{handle}/subscribe/checkout", s.authed(s.subscribeCheckout))
	mux.HandleFunc("POST /v1/users/{handle}/subscribe/apple", s.authed(s.subscribeApple))
	mux.HandleFunc("POST /v1/users/{handle}/subscribe/google", s.authed(s.subscribeGoogle))
	mux.HandleFunc("DELETE /v1/users/{handle}/subscription", s.authed(s.cancelSubscription))
	mux.HandleFunc("GET /v1/users/{handle}/cards", s.userCards)
	mux.HandleFunc("POST /v1/posts/{id}/report", s.authed(s.reportPost))
	mux.HandleFunc("GET /v1/moderation/cards", s.moderator(s.reportedCards))
	mux.HandleFunc("POST /v1/moderation/cards/{id}/hide", s.moderator(s.moderateCard(true)))
	mux.HandleFunc("POST /v1/moderation/cards/{id}/restore", s.moderator(s.moderateCard(false)))

	mux.HandleFunc("GET /v1/review/due", s.authed(s.dueReviews))
	mux.HandleFunc("POST /v1/review/{cardId}", s.authed(s.grade))
	mux.HandleFunc("GET /v1/quiz", s.authed(s.quiz))

	mux.HandleFunc("POST /v1/contributions", s.authed(s.contribute))
	mux.HandleFunc("GET /v1/contributions/mine", s.authed(s.myContributions))
	mux.HandleFunc("GET /v1/moderation/queue", s.moderator(s.queue))
	mux.HandleFunc("POST /v1/moderation/{id}/approve", s.moderator(s.approve))
	mux.HandleFunc("POST /v1/moderation/{id}/reject", s.moderator(s.reject))
	mux.HandleFunc("GET /v1/moderation/comments", s.moderator(s.reportedComments))
	mux.HandleFunc("POST /v1/moderation/comments/{id}/hide", s.moderator(s.moderateComment(true)))
	mux.HandleFunc("POST /v1/moderation/comments/{id}/restore", s.moderator(s.moderateComment(false)))

	mux.HandleFunc("POST /v1/agent/chat", s.authed(s.chat))

	mux.HandleFunc("GET /v1/ai", s.aiStatus)
	mux.HandleFunc("POST /v1/ai/chat", s.authed(s.aiChat))
	mux.HandleFunc("POST /v1/ai/voice", s.authed(s.aiVoice))
	mux.HandleFunc("POST /v1/ai/messages/{id}/speech", s.authed(s.aiSpeech))
	mux.HandleFunc("GET /v1/ai/conversations", s.authed(s.aiConversations))
	mux.HandleFunc("GET /v1/ai/conversations/{id}", s.authed(s.aiConversation))
	mux.HandleFunc("DELETE /v1/ai/conversations/{id}", s.authed(s.deleteAIConversation))
	mux.HandleFunc("GET /v1/ai/usage", s.authed(s.aiUsage))
	mux.HandleFunc("POST /v1/ai/topups/checkout", s.authed(s.topUpCheckout))
	mux.HandleFunc("GET /v1/ai/topups/{id}", s.authed(s.topUp))
	mux.HandleFunc("POST /v1/ai/topups/apple", s.authed(s.topUpApple))
	mux.HandleFunc("POST /v1/ai/topups/google", s.authed(s.topUpGoogle))

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
