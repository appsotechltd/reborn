package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// SummaryEvery is how many card posts come between summary posts in the timeline.
const SummaryEvery = 6

// SummaryItem is a summary post in the timeline. Timelines only carry them
// when asked (?with=summaries), so older clients keep getting card posts only.
type SummaryItem struct {
	ID      string        `json:"id"`
	Kind    string        `json:"kind"`
	Summary store.Summary `json:"summary"`
}

// weave puts a summary before every SummaryEvery-th card post, counting from
// the start of the timeline, so pages line up: the summary at timeline
// position k*SummaryEvery is the k-th (1-based) summary in summaryAt's order.
func weave(posts []store.Post, offset int, summaryAt func(k int) *store.Summary) []any {
	out := make([]any, 0, len(posts)+len(posts)/SummaryEvery+1)
	for i, p := range posts {
		if pos := offset + i; pos > 0 && pos%SummaryEvery == 0 {
			if sm := summaryAt(pos/SummaryEvery - 1); sm != nil {
				out = append(out, SummaryItem{ID: "summary:" + sm.ID, Kind: "summary", Summary: *sm})
			}
		}
		out = append(out, p)
	}
	return out
}

// timelineSummaries loads the summaries a page of the timeline needs.
func (s *Server) timelineSummaries(r *http.Request, topics []string, snapshot time.Time, offset, n int) (func(int) *store.Summary, error) {
	none := func(int) *store.Summary { return nil }
	// Slot k sits before the card at timeline position (k+1)*SummaryEvery.
	first := (max(offset, 1)+SummaryEvery-1)/SummaryEvery - 1
	last := (offset+n-1)/SummaryEvery - 1
	if n == 0 || last < first {
		return none, nil
	}
	sums, err := s.Store.SummaryFeed(r.Context(), store.SummaryFeedParams{UserID: userID(r), Topics: topics,
		TopicsOnly: r.URL.Query().Get("topics") != "", Day: s.today(), Snapshot: snapshot,
		Offset: first, Limit: last - first + 1})
	if err != nil {
		return nil, err
	}
	return func(k int) *store.Summary {
		if i := k - first; i >= 0 && i < len(sums) {
			return &sums[i]
		}
		return nil
	}, nil
}

func (s *Server) summaries(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	kind, topic := q.Get("kind"), q.Get("topic")
	if kind != "" && kind != "book" && kind != "topic" {
		writeError(w, http.StatusBadRequest, "bad_request", "kind must be book or topic")
		return
	}
	if topic != "" && !content.IsTopic(topic) {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown topic")
		return
	}
	offset, limit, ok := offsetPage(w, r, 20)
	if !ok {
		return
	}
	sums, err := s.Store.Summaries(r.Context(), store.SummaryListParams{UserID: userID(r), Kind: kind, Topic: topic,
		Source: q.Get("source"), Offset: offset, Limit: limit})
	if err != nil {
		s.fail(w, r, err, "summaries")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"summaries": sums, "next_cursor": nextOffset(len(sums), offset, limit)})
}

func (s *Server) summary(w http.ResponseWriter, r *http.Request) {
	sm, err := s.Store.GetSummary(r.Context(), r.PathValue("id"), userID(r))
	if err != nil {
		s.fail(w, r, err, "summary")
		return
	}
	writeJSON(w, http.StatusOK, sm)
}

func (s *Server) summaryProgress(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Position *int `json:"position"`
		Finished bool `json:"finished"`
	}
	if !decode(w, r, &in) {
		return
	}
	if in.Position == nil {
		writeError(w, http.StatusBadRequest, "bad_request", "position is required")
		return
	}
	p, err := s.Store.SetSummaryProgress(r.Context(), userID(r), r.PathValue("id"), *in.Position, in.Finished, s.Now())
	if errors.Is(err, store.ErrBadPosition) {
		writeError(w, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	if err != nil {
		s.fail(w, r, err, "summary")
		return
	}
	writeJSON(w, http.StatusOK, p)
}
