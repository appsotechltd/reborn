package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/push"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n-1]) + "…"
}

// --- notifications ---

// notify stores an inbox entry and pushes it to the user's devices in the
// background. setting is the user's notification switch that governs the push.
func (s *Server) notify(n store.NewNotification, setting string, data map[string]string) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		stored, err := s.Store.AddNotification(ctx, n)
		if err != nil {
			slog.Error("store notification", "err", err)
			return
		}
		if !stored {
			return
		}
		s.pushTo(ctx, n.UserID, setting, push.Message{Title: "Reborn", Body: n.Text, Data: data})
	}()
}

func (s *Server) pushTo(ctx context.Context, userID, setting string, m push.Message) {
	if s.Push == nil {
		return
	}
	tokens, err := s.Store.DeviceTokens(ctx, userID, setting)
	if err != nil {
		slog.Error("device tokens", "err", err)
		return
	}
	for _, t := range tokens {
		err := s.Push.Send(ctx, t, m)
		if errors.Is(err, push.ErrUnregistered) {
			_ = s.Store.RemoveDevice(ctx, "", t)
		} else if err != nil {
			slog.Warn("push failed", "err", err)
		}
	}
}

func (s *Server) notifications(w http.ResponseWriter, r *http.Request) {
	list, unread, err := s.Store.Notifications(r.Context(), userID(r), intParam(r, "limit", 50, 1, 100))
	if err != nil {
		s.fail(w, r, err, "notifications")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notifications": list, "unread": unread})
}

func (s *Server) readNotifications(w http.ResponseWriter, r *http.Request) {
	var in struct {
		IDs []string `json:"ids"`
	}
	if r.ContentLength != 0 && !decode(w, r, &in) {
		return
	}
	if in.IDs == nil {
		in.IDs = []string{}
	}
	if err := s.Store.MarkNotificationsRead(r.Context(), userID(r), in.IDs, s.Now()); err != nil {
		s.fail(w, r, err, "notifications")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) registerDevice(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Platform string `json:"platform"`
		Token    string `json:"token"`
	}
	if !decode(w, r, &in) {
		return
	}
	if in.Platform != "ios" && in.Platform != "android" && in.Platform != "web" {
		writeError(w, http.StatusBadRequest, "bad_request", "platform must be ios, android or web")
		return
	}
	if in.Token == "" || len(in.Token) > 4096 {
		writeError(w, http.StatusBadRequest, "bad_request", "token is required")
		return
	}
	if err := s.Store.RegisterDevice(r.Context(), userID(r), in.Platform, in.Token); err != nil {
		s.fail(w, r, err, "device")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) removeDevice(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.RemoveDevice(r.Context(), userID(r), r.PathValue("token")); err != nil {
		s.fail(w, r, err, "device")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RunDailyPushes sends each user their daily idea once a day after 8am in
// their timezone, until ctx ends. It is safe to run on several servers.
func (s *Server) RunDailyPushes(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		s.sendDailyPushes(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func (s *Server) sendDailyPushes(ctx context.Context) {
	if s.Push == nil {
		return
	}
	for {
		due, err := s.Store.DueDailyPushes(ctx, s.Now(), 200)
		if err != nil {
			slog.Error("daily pushes", "err", err)
			return
		}
		for _, d := range due {
			card, err := s.Store.DailyCard(ctx, d.UserID, d.Topics, d.Day)
			if err != nil {
				continue
			}
			text := "Today's idea: " + card.Title
			if _, err := s.Store.AddNotification(ctx, store.NewNotification{UserID: d.UserID, Kind: "daily", PostID: card.ID, Text: text}); err != nil {
				slog.Error("daily notification", "err", err)
			}
			s.pushTo(ctx, d.UserID, "daily", push.Message{Title: "Your daily idea", Body: card.Title, Data: map[string]string{"post_id": card.ID}})
		}
		if len(due) < 200 {
			return
		}
	}
}

// --- streaks and referrals ---

// recordActivity counts ideas read toward the streak, and gives referral
// rewards once a referred reader has been active on three days.
func (s *Server) recordActivity(ctx context.Context, uid string, n int) {
	days, err := s.Store.BumpActivity(ctx, uid, n, s.Now())
	if err != nil {
		slog.Error("activity", "err", err)
		return
	}
	if days < 3 {
		return
	}
	referrer, err := s.Store.ClaimReferralReward(ctx, uid, s.Now())
	if err != nil {
		slog.Error("referral reward", "err", err)
		return
	}
	if referrer != "" {
		s.notify(store.NewNotification{UserID: referrer, Kind: "reward", ActorID: uid,
			Text: "A friend you invited is reading on Reborn. You both get a free week of Premium."}, "follows", nil)
	}
}

func (s *Server) streak(w http.ResponseWriter, r *http.Request) {
	st, err := s.Store.StreakOf(r.Context(), userID(r), s.Now())
	if err != nil {
		s.fail(w, r, err, "streak")
		return
	}
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) referrals(w http.ResponseWriter, r *http.Request) {
	ref, err := s.Store.Referrals(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "referrals")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"code": ref.Code, "invited": ref.Invited, "rewarded": ref.Rewarded,
		"link":        s.WebBaseURL + "/join?ref=" + url.QueryEscape(ref.Code),
		"reward_days": store.ReferralRewardDays,
	})
}

// --- blocking ---

func (s *Server) setBlock(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Kind string `json:"kind"`
	}
	if !decode(w, r, &in) {
		return
	}
	if in.Kind != "block" && in.Kind != "mute" {
		writeError(w, http.StatusBadRequest, "bad_request", "kind must be block or mute")
		return
	}
	s.applyBlock(w, r, in.Kind)
}

func (s *Server) clearBlock(w http.ResponseWriter, r *http.Request) { s.applyBlock(w, r, "") }

func (s *Server) applyBlock(w http.ResponseWriter, r *http.Request, kind string) {
	err := s.Store.SetBlock(r.Context(), userID(r), r.PathValue("userId"), kind)
	if err == store.ErrConflict {
		writeError(w, http.StatusBadRequest, "bad_request", "you can't block yourself")
		return
	}
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) myBlocks(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.Blocks(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "blocks")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"blocks": list})
}

// --- discover ---

func (s *Server) trending(w http.ResponseWriter, r *http.Request) {
	topic := r.URL.Query().Get("topic")
	if topic != "" && !content.IsTopic(topic) {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown topic")
		return
	}
	days := intParam(r, "days", 7, 1, 30)
	posts, err := s.Store.Trending(r.Context(), userID(r), topic, s.Now().AddDate(0, 0, -days), intParam(r, "limit", 20, 1, 50))
	if err != nil {
		s.fail(w, r, err, "trending")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"posts": posts})
}

func (s *Server) discover(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	uid := userID(r)
	trending, err := s.Store.Trending(ctx, uid, "", s.Now().AddDate(0, 0, -7), 10)
	if err != nil {
		s.fail(w, r, err, "discover")
		return
	}
	fresh, err := s.Store.NewPosts(ctx, uid, 10)
	if err != nil {
		s.fail(w, r, err, "discover")
		return
	}
	var popular struct {
		Books   []store.PopularSource `json:"books"`
		Authors []store.PopularAuthor `json:"authors"`
	}
	if !s.Cache.GetJSON(ctx, "discover:popular", &popular) {
		if popular.Books, err = s.Store.PopularSources(ctx, 12); err != nil {
			s.fail(w, r, err, "discover")
			return
		}
		if popular.Authors, err = s.Store.PopularAuthors(ctx, 12); err != nil {
			s.fail(w, r, err, "discover")
			return
		}
		s.Cache.SetJSON(ctx, "discover:popular", popular, 10*time.Minute)
	}
	circles, err := s.Store.Circles(ctx, uid, "", false, 6)
	if err != nil {
		s.fail(w, r, err, "discover")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"trending": trending, "new": fresh, "books": popular.Books, "authors": popular.Authors, "circles": circles})
}

// --- public stashes ---

func (s *Server) publicStash(w http.ResponseWriter, r *http.Request) {
	st, cards, err := s.Store.GetPublicStash(r.Context(), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "stash")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"stash": st, "cards": cards})
}

func (s *Server) profileStashes(w http.ResponseWriter, r *http.Request) {
	p, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	list, err := s.Store.PublicStashes(r.Context(), p.ID)
	if err != nil {
		s.fail(w, r, err, "stashes")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"stashes": list})
}

// --- circles ---

func (s *Server) circles(w http.ResponseWriter, r *http.Request) {
	mine := r.URL.Query().Get("mine") == "1" || r.URL.Query().Get("mine") == "true"
	if mine && userID(r) == "" {
		writeError(w, http.StatusUnauthorized, "unauthorized", "sign in required")
		return
	}
	list, err := s.Store.Circles(r.Context(), userID(r), r.URL.Query().Get("source"), mine, intParam(r, "limit", 30, 1, 100))
	if err != nil {
		s.fail(w, r, err, "circles")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"circles": list})
}

func (s *Server) createCircle(w http.ResponseWriter, r *http.Request) {
	var in struct {
		SourceID    string `json:"source_id"`
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if !decode(w, r, &in) {
		return
	}
	name, desc := strings.TrimSpace(in.Name), strings.TrimSpace(in.Description)
	if name == "" || utf8.RuneCountInString(name) > 80 || utf8.RuneCountInString(desc) > 500 {
		writeError(w, http.StatusBadRequest, "bad_request", "name must be 1-80 characters and description at most 500")
		return
	}
	if !s.Cache.Allow(r.Context(), "circle:"+userID(r), 5, 24*time.Hour) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "too many new circles today")
		return
	}
	c, err := s.Store.CreateCircle(r.Context(), userID(r), in.SourceID, name, desc)
	if err != nil {
		s.fail(w, r, err, "book")
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) circle(w http.ResponseWriter, r *http.Request) {
	c, err := s.Store.GetCircle(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "circle")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) circleMembers(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.CircleMembers(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "circle")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"members": list})
}

func (s *Server) joinCircle(w http.ResponseWriter, r *http.Request) {
	err := s.Store.JoinCircle(r.Context(), userID(r), r.PathValue("id"))
	if err == store.ErrFull {
		writeError(w, http.StatusConflict, "circle_full", "this circle is full")
		return
	}
	if err != nil {
		s.fail(w, r, err, "circle")
		return
	}
	s.circle(w, r)
}

func (s *Server) leaveCircle(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.LeaveCircle(r.Context(), userID(r), r.PathValue("id")); err != nil {
		s.fail(w, r, err, "circle membership")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) circleMessages(w http.ResponseWriter, r *http.Request) {
	var before *time.Time
	if b := r.URL.Query().Get("before"); b != "" {
		t, err := time.Parse(time.RFC3339Nano, b)
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad_request", "before must be an RFC 3339 time")
			return
		}
		before = &t
	}
	list, err := s.Store.CircleMessages(r.Context(), userID(r), r.PathValue("id"), before, intParam(r, "limit", 50, 1, 100))
	if err != nil {
		s.fail(w, r, err, "circle")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": list})
}

func (s *Server) addCircleMessage(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Body   string `json:"body"`
		PostID string `json:"post_id"`
	}
	if !decode(w, r, &in) {
		return
	}
	body := strings.TrimSpace(in.Body)
	if body == "" || utf8.RuneCountInString(body) > 2000 {
		writeError(w, http.StatusBadRequest, "bad_request", "body must be 1-2000 characters")
		return
	}
	if !s.Cache.Allow(r.Context(), "circlemsg:"+userID(r), 60, time.Hour) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "too many messages, try again later")
		return
	}
	id := r.PathValue("id")
	m, members, err := s.Store.AddCircleMessage(r.Context(), userID(r), id, body, in.PostID)
	if err != nil {
		s.fail(w, r, err, "circle or post")
		return
	}
	if c, err := s.Store.GetCircle(r.Context(), "", id); err == nil {
		text := m.Author.DisplayName + " in " + c.Name + ": " + truncateRunes(body, 80)
		for _, uid := range members {
			s.notify(store.NewNotification{UserID: uid, Kind: "circle", ActorID: m.Author.ID, CircleID: id, Text: text},
				"circles", map[string]string{"circle_id": id})
		}
	}
	writeJSON(w, http.StatusCreated, m)
}

func (s *Server) deleteCircleMessage(w http.ResponseWriter, r *http.Request) {
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	if err := s.Store.DeleteCircleMessage(r.Context(), u.ID, r.PathValue("id"), r.PathValue("msgId"), u.Role == "moderator"); err != nil {
		s.fail(w, r, err, "message")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- moderator dashboard ---

func (s *Server) adminStats(w http.ResponseWriter, r *http.Request) {
	var st store.Stats
	if !s.Cache.GetJSON(r.Context(), "admin:stats", &st) {
		var err error
		if st, err = s.Store.AdminStats(r.Context(), s.Now()); err != nil {
			s.fail(w, r, err, "stats")
			return
		}
		s.Cache.SetJSON(r.Context(), "admin:stats", st, time.Minute)
	}
	writeJSON(w, http.StatusOK, st)
}
