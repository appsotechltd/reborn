package api

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/store"
)

// --- timeline and posts ---

// timelineCursor pins the moment the first page was read, so posts marked seen
// while scrolling don't shift later pages.
func parseTimelineCursor(c string, now time.Time) (time.Time, int, bool) {
	if c == "" {
		return now, 0, true
	}
	ts, off, ok := strings.Cut(c, "-")
	if !ok {
		return time.Time{}, 0, false
	}
	sec, err1 := strconv.ParseInt(ts, 10, 64)
	n, err2 := strconv.Atoi(off)
	if err1 != nil || err2 != nil || n < 0 {
		return time.Time{}, 0, false
	}
	return time.Unix(sec, 0), n, true
}

func (s *Server) timeline(w http.ResponseWriter, r *http.Request) {
	topics, err := s.userTopics(r)
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	snapshot, offset, ok := parseTimelineCursor(r.URL.Query().Get("cursor"), s.Now())
	if !ok {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid cursor")
		return
	}
	limit := intParam(r, "limit", 20, 1, 50)
	posts, err := s.Store.Timeline(r.Context(), store.TimelineParams{UserID: userID(r), Topics: topics, Day: s.today(),
		Snapshot: snapshot, Offset: offset, Limit: limit})
	if err != nil {
		s.fail(w, r, err, "timeline")
		return
	}
	var next *string
	if len(posts) == limit {
		n := fmt.Sprintf("%d-%d", snapshot.Unix(), offset+limit)
		next = &n
	}
	if r.URL.Query().Get("with") != "summaries" {
		writeJSON(w, http.StatusOK, map[string]any{"posts": posts, "next_cursor": next})
		return
	}
	summaryAt, err := s.timelineSummaries(r, topics, snapshot, offset, len(posts))
	if err != nil {
		s.fail(w, r, err, "timeline")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"posts": weave(posts, offset, summaryAt), "next_cursor": next})
}

func (s *Server) markSeen(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PostIDs []string `json:"post_ids"`
	}
	if !decode(w, r, &in) {
		return
	}
	if len(in.PostIDs) == 0 || len(in.PostIDs) > 100 {
		writeError(w, http.StatusBadRequest, "bad_request", "post_ids must list 1-100 posts")
		return
	}
	if _, err := s.Store.MarkSeen(r.Context(), userID(r), in.PostIDs, s.Now()); err != nil {
		s.fail(w, r, err, "posts")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) post(w http.ResponseWriter, r *http.Request) {
	p, err := s.Store.GetPost(r.Context(), r.PathValue("id"), userID(r))
	if err != nil {
		s.fail(w, r, err, "post")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

// offsetPage reads ?cursor= as an offset and ?limit=.
func offsetPage(w http.ResponseWriter, r *http.Request, def int) (offset, limit int, ok bool) {
	limit = intParam(r, "limit", def, 1, 50)
	if c := r.URL.Query().Get("cursor"); c != "" {
		var err error
		if offset, err = strconv.Atoi(c); err != nil || offset < 0 {
			writeError(w, http.StatusBadRequest, "bad_request", "invalid cursor")
			return 0, 0, false
		}
	}
	return offset, limit, true
}

func nextOffset(n, offset, limit int) *string {
	if n < limit {
		return nil
	}
	c := strconv.Itoa(offset + limit)
	return &c
}

func (s *Server) setFavorite(on bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := s.Store.SetFavorite(r.Context(), userID(r), r.PathValue("id"), on); err != nil {
			s.fail(w, r, err, "post")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func (s *Server) setReaction(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Kind string `json:"kind"`
	}
	if !decode(w, r, &in) {
		return
	}
	if !store.IsReaction(in.Kind) {
		writeError(w, http.StatusBadRequest, "bad_request", "kind must be one of "+strings.Join(store.Reactions, ", "))
		return
	}
	if err := s.Store.SetReaction(r.Context(), userID(r), r.PathValue("id"), in.Kind); err != nil {
		s.fail(w, r, err, "post")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) clearReaction(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.SetReaction(r.Context(), userID(r), r.PathValue("id"), ""); err != nil {
		s.fail(w, r, err, "post")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// shareChannels are the share targets the apps count.
var shareChannels = map[string]bool{"facebook": true, "x": true, "whatsapp": true, "linkedin": true, "telegram": true,
	"email": true, "instagram": true, "copy_link": true, "native": true, "embed": true}

func (s *Server) share(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Channel string `json:"channel"`
	}
	if !decode(w, r, &in) {
		return
	}
	if !shareChannels[in.Channel] {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown channel")
		return
	}
	who := userID(r)
	if who == "" {
		who = clientIP(r)
	}
	if !s.Cache.Allow(r.Context(), "share:"+who, 60, time.Hour) {
		w.WriteHeader(http.StatusNoContent) // over the limit: don't count it, but don't break the share either
		return
	}
	if err := s.Store.RecordShare(r.Context(), userID(r), r.PathValue("id"), in.Channel); err != nil {
		s.fail(w, r, err, "post")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func clientIP(r *http.Request) string {
	if f := r.Header.Get("X-Forwarded-For"); f != "" {
		return strings.TrimSpace(strings.Split(f, ",")[0])
	}
	host := r.RemoteAddr
	if i := strings.LastIndex(host, ":"); i > 0 {
		host = host[:i]
	}
	return host
}

// --- comments ---

func (s *Server) comments(w http.ResponseWriter, r *http.Request) {
	offset, limit, ok := offsetPage(w, r, 50)
	if !ok {
		return
	}
	list, err := s.Store.Comments(r.Context(), r.PathValue("id"), userID(r), offset, limit)
	if err != nil {
		s.fail(w, r, err, "post")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"comments": list, "next_cursor": nextOffset(len(list), offset, limit)})
}

func (s *Server) addComment(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Body     string  `json:"body"`
		ParentID *string `json:"parent_id"`
	}
	if !decode(w, r, &in) {
		return
	}
	body := strings.TrimSpace(in.Body)
	if body == "" || utf8.RuneCountInString(body) > 1000 {
		writeError(w, http.StatusBadRequest, "bad_request", "body must be 1-1000 characters")
		return
	}
	if !s.Cache.Allow(r.Context(), "comment:"+userID(r), 20, time.Hour) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "too many comments, try again later")
		return
	}
	c, repliedTo, err := s.Store.AddComment(r.Context(), userID(r), r.PathValue("id"), in.ParentID, body)
	if errors.Is(err, store.ErrBlocked) {
		writeError(w, http.StatusForbidden, "blocked", "you can't reply to this person")
		return
	}
	if err != nil {
		s.fail(w, r, err, "post or parent comment")
		return
	}
	if repliedTo != "" && repliedTo != c.Author.ID {
		text := c.Author.DisplayName + " replied to your comment: " + truncateRunes(c.Body, 80)
		s.notify(store.NewNotification{UserID: repliedTo, Kind: "reply", ActorID: c.Author.ID, PostID: c.PostID, CommentID: c.ID, Text: text},
			"replies", map[string]string{"post_id": c.PostID, "comment_id": c.ID})
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) deleteComment(w http.ResponseWriter, r *http.Request) {
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	if err := s.Store.DeleteComment(r.Context(), u.ID, r.PathValue("id"), u.Role == "moderator"); err != nil {
		s.fail(w, r, err, "comment")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) reportComment(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Reason string `json:"reason"`
	}
	if r.ContentLength != 0 && !decode(w, r, &in) {
		return
	}
	if utf8.RuneCountInString(in.Reason) > 300 {
		writeError(w, http.StatusBadRequest, "bad_request", "reason must be at most 300 characters")
		return
	}
	if err := s.Store.ReportComment(r.Context(), userID(r), r.PathValue("id"), strings.TrimSpace(in.Reason)); err != nil {
		s.fail(w, r, err, "comment")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) reportedComments(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ReportedComments(r.Context())
	if err != nil {
		s.fail(w, r, err, "comments")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"comments": list})
}

func (s *Server) moderateComment(hide bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := s.Store.ModerateComment(r.Context(), r.PathValue("id"), hide); err != nil {
			s.fail(w, r, err, "comment")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// --- follows and profiles ---

func (s *Server) setFollow(on bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		kind, target := r.PathValue("kind"), r.PathValue("target")
		if kind != "user" && kind != "source" && kind != "author" {
			writeError(w, http.StatusBadRequest, "bad_request", "kind must be user, source or author")
			return
		}
		if target == "" || len(target) > 200 {
			writeError(w, http.StatusBadRequest, "bad_request", "target is required")
			return
		}
		err := s.Store.SetFollow(r.Context(), userID(r), kind, target, on)
		if err == store.ErrConflict {
			writeError(w, http.StatusBadRequest, "bad_request", "you can't follow yourself")
			return
		}
		if err == store.ErrBlocked {
			writeError(w, http.StatusNotFound, "not_found", "user not found")
			return
		}
		if err != nil {
			s.fail(w, r, err, kind)
			return
		}
		if on && kind == "user" {
			if me, err := s.Store.UserByID(r.Context(), userID(r)); err == nil {
				s.notify(store.NewNotification{UserID: target, Kind: "follow", ActorID: me.ID, Text: me.DisplayName + " started following you"},
					"follows", map[string]string{"handle": me.Handle})
			}
		}
		st, err := s.Store.FollowStateOf(r.Context(), kind, target, userID(r))
		if err != nil {
			s.fail(w, r, err, kind)
			return
		}
		writeJSON(w, http.StatusOK, st)
	}
}

func (s *Server) myFollowing(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.Following(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "follows")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"following": list})
}

func (s *Server) myFavorites(w http.ResponseWriter, r *http.Request) {
	offset, limit, ok := offsetPage(w, r, 20)
	if !ok {
		return
	}
	posts, err := s.Store.Favorites(r.Context(), userID(r), userID(r), offset, limit)
	if err != nil {
		s.fail(w, r, err, "favorites")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"posts": posts, "next_cursor": nextOffset(len(posts), offset, limit)})
}

func (s *Server) profile(w http.ResponseWriter, r *http.Request) {
	p, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) profileFavorites(w http.ResponseWriter, r *http.Request) {
	p, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	offset, limit, ok := offsetPage(w, r, 20)
	if !ok {
		return
	}
	posts, err := s.Store.Favorites(r.Context(), p.ID, userID(r), offset, limit)
	if err != nil {
		s.fail(w, r, err, "favorites")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"posts": posts, "next_cursor": nextOffset(len(posts), offset, limit)})
}

func (s *Server) profileFollowers(w http.ResponseWriter, r *http.Request) {
	p, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	offset, limit, ok := offsetPage(w, r, 50)
	if !ok {
		return
	}
	list, err := s.Store.Followers(r.Context(), "user", p.ID, offset, limit)
	if err != nil {
		s.fail(w, r, err, "followers")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": list, "next_cursor": nextOffset(len(list), offset, limit)})
}

func (s *Server) author(w http.ResponseWriter, r *http.Request) {
	a, err := s.Store.Author(r.Context(), r.PathValue("name"), userID(r))
	if err != nil {
		s.fail(w, r, err, "author")
		return
	}
	writeJSON(w, http.StatusOK, a)
}
