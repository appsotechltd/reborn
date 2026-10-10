package api

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

func (s *Server) topics(w http.ResponseWriter, r *http.Request) {
	var ts []store.TopicCount
	if !s.Cache.GetJSON(r.Context(), "topics", &ts) {
		var err error
		if ts, err = s.Store.Topics(r.Context()); err != nil {
			s.fail(w, r, err, "topics")
			return
		}
		s.Cache.SetJSON(r.Context(), "topics", ts, 5*time.Minute)
	}
	writeJSON(w, http.StatusOK, map[string]any{"topics": ts})
}

func intParam(r *http.Request, name string, def, lo, hi int) int {
	v, err := strconv.Atoi(r.URL.Query().Get(name))
	if err != nil {
		return def
	}
	return max(lo, min(hi, v))
}

// userTopics returns the topics in ?topics=, else the signed-in user's topics.
func (s *Server) userTopics(r *http.Request) ([]string, error) {
	if q := r.URL.Query().Get("topics"); q != "" {
		var ts []string
		for _, t := range splitList(q) {
			if content.IsTopic(t) {
				ts = append(ts, t)
			}
		}
		return ts, nil
	}
	if id := userID(r); id != "" {
		u, err := s.Store.UserByID(r.Context(), id)
		if err != nil {
			return nil, err
		}
		return u.Topics, nil
	}
	return nil, nil
}

func (s *Server) today() string { return s.Now().UTC().Format("2006-01-02") }

func (s *Server) feed(w http.ResponseWriter, r *http.Request) {
	topics, err := s.userTopics(r)
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	limit := intParam(r, "limit", 20, 1, 50)
	offset := 0
	if c := r.URL.Query().Get("cursor"); c != "" {
		if offset, err = strconv.Atoi(c); err != nil || offset < 0 {
			writeError(w, http.StatusBadRequest, "bad_request", "invalid cursor")
			return
		}
	}
	cards, err := s.Store.Feed(r.Context(), store.FeedParams{UserID: userID(r), Topics: topics, Day: s.today(), Offset: offset, Limit: limit})
	if err != nil {
		s.fail(w, r, err, "feed")
		return
	}
	var next *string
	if len(cards) == limit {
		n := strconv.Itoa(offset + limit)
		next = &n
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": cards, "next_cursor": next})
}

func (s *Server) daily(w http.ResponseWriter, r *http.Request) {
	day := s.today()
	uid := userID(r)
	key := "daily:" + day + ":" + uid
	var card store.Card
	if !s.Cache.GetJSON(r.Context(), key, &card) {
		topics, err := s.userTopics(r)
		if err != nil {
			s.fail(w, r, err, "user")
			return
		}
		if card, err = s.Store.DailyCard(r.Context(), uid, topics, day); err != nil {
			s.fail(w, r, err, "daily idea")
			return
		}
		s.Cache.SetJSON(r.Context(), key, card, 36*time.Hour)
	}
	writeJSON(w, http.StatusOK, map[string]any{"date": day, "card": card})
}

func (s *Server) card(w http.ResponseWriter, r *http.Request) {
	c, err := s.Store.GetCard(r.Context(), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) cardsByIDs(w http.ResponseWriter, r *http.Request) {
	ids := splitList(r.URL.Query().Get("ids"))
	if len(ids) == 0 || len(ids) > 100 {
		writeError(w, http.StatusBadRequest, "bad_request", "ids must list 1-100 card ids")
		return
	}
	cards, err := s.Store.GetCards(r.Context(), ids)
	if err != nil {
		s.fail(w, r, err, "cards")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": cards})
}

func (s *Server) view(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.RecordView(r.Context(), userID(r), r.PathValue("id")); err != nil {
		s.fail(w, r, err, "card")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) source(w http.ResponseWriter, r *http.Request) {
	src, cards, err := s.Store.SourceCards(r.Context(), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "source")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"source": src, "cards": cards})
}

func (s *Server) search(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" || len(q) > 200 {
		writeError(w, http.StatusBadRequest, "bad_request", "q must be 1-200 characters")
		return
	}
	topic := r.URL.Query().Get("topic")
	if topic != "" && !content.IsTopic(topic) {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown topic")
		return
	}
	p := store.SearchParams{Query: q, Topic: topic, Limit: intParam(r, "limit", 20, 1, 50)}
	if s.Embedder != nil {
		if vecs, err := s.Embedder.Embed(r.Context(), []string{q}, "query"); err == nil && len(vecs) == 1 {
			p.QueryVector = vecs[0]
		}
	}
	cards, err := s.Store.Search(r.Context(), p)
	if err != nil {
		s.fail(w, r, err, "search")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": cards})
}
