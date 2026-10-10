package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/agent"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/srs"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// --- stashes ---

func (s *Server) listStashes(w http.ResponseWriter, r *http.Request) {
	st, err := s.Store.Stashes(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "stashes")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"stashes": st})
}

type stashInput struct {
	Name        *string `json:"name"`
	Description *string `json:"description"`
	IsPublic    *bool   `json:"is_public"`
}

func (in *stashInput) clean(requireName bool) string {
	if in.Name != nil {
		n := strings.TrimSpace(*in.Name)
		in.Name = &n
		if n == "" || utf8.RuneCountInString(n) > 80 {
			return "name must be 1-80 characters"
		}
	} else if requireName {
		return "name is required"
	}
	if in.Description != nil && utf8.RuneCountInString(*in.Description) > 500 {
		return "description must be at most 500 characters"
	}
	return ""
}

func (s *Server) createStash(w http.ResponseWriter, r *http.Request) {
	var in stashInput
	if !decode(w, r, &in) {
		return
	}
	if msg := in.clean(true); msg != "" {
		writeError(w, http.StatusBadRequest, "bad_request", msg)
		return
	}
	desc := ""
	if in.Description != nil {
		desc = *in.Description
	}
	st, err := s.Store.CreateStash(r.Context(), userID(r), *in.Name, desc)
	if err == nil && in.IsPublic != nil && *in.IsPublic {
		st, err = s.Store.UpdateStash(r.Context(), userID(r), st.ID, nil, nil, in.IsPublic)
	}
	if err != nil {
		s.fail(w, r, err, "stash")
		return
	}
	writeJSON(w, http.StatusCreated, st)
}

func (s *Server) getStash(w http.ResponseWriter, r *http.Request) {
	st, err := s.Store.GetStash(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "stash")
		return
	}
	cards, err := s.Store.StashCards(r.Context(), userID(r), st.ID)
	if err != nil {
		s.fail(w, r, err, "stash")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"stash": st, "cards": cards})
}

func (s *Server) updateStash(w http.ResponseWriter, r *http.Request) {
	var in stashInput
	if !decode(w, r, &in) {
		return
	}
	if msg := in.clean(false); msg != "" {
		writeError(w, http.StatusBadRequest, "bad_request", msg)
		return
	}
	st, err := s.Store.UpdateStash(r.Context(), userID(r), r.PathValue("id"), in.Name, in.Description, in.IsPublic)
	if err != nil {
		s.fail(w, r, err, "stash")
		return
	}
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) deleteStash(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DeleteStash(r.Context(), userID(r), r.PathValue("id")); err != nil {
		s.fail(w, r, err, "stash")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) addToStash(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.AddToStash(r.Context(), userID(r), r.PathValue("id"), r.PathValue("cardId"), s.Now()); err != nil {
		s.fail(w, r, err, "stash or card")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) removeFromStash(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.RemoveFromStash(r.Context(), userID(r), r.PathValue("id"), r.PathValue("cardId")); err != nil {
		s.fail(w, r, err, "stash card")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- review & quiz ---

func (s *Server) dueReviews(w http.ResponseWriter, r *http.Request) {
	items, total, err := s.Store.DueReviews(r.Context(), userID(r), s.Now(), intParam(r, "limit", 20, 1, 100))
	if err != nil {
		s.fail(w, r, err, "reviews")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "due_count": total})
}

func (s *Server) grade(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Grade srs.Grade `json:"grade"`
	}
	if !decode(w, r, &in) {
		return
	}
	if !in.Grade.Valid() {
		writeError(w, http.StatusBadRequest, "bad_request", "grade must be again, hard, good or easy")
		return
	}
	st, err := s.Store.Grade(r.Context(), userID(r), r.PathValue("cardId"), in.Grade, s.Now())
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"due_at": st.DueAt, "interval_days": st.IntervalDays, "reps": st.Reps})
}

func (s *Server) quiz(w http.ResponseWriter, r *http.Request) {
	topic := r.URL.Query().Get("topic")
	if topic != "" && !content.IsTopic(topic) {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown topic")
		return
	}
	cards, err := s.Store.QuizCards(r.Context(), userID(r), topic, intParam(r, "limit", 5, 1, 20))
	if err != nil {
		s.fail(w, r, err, "quiz")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": cards})
}

// --- contributions & moderation ---

func (s *Server) contribute(w http.ResponseWriter, r *http.Request) {
	var in store.Contribution
	if !decode(w, r, &in) {
		return
	}
	if !s.Cache.Allow(r.Context(), "contrib:"+userID(r), 20, 24*time.Hour) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "daily contribution limit reached")
		return
	}
	// Reuse the library validator: a contribution must be a valid card from a
	// valid original-summary source.
	src := content.Source{
		ID: "contribution", Title: in.Source.Title, Authors: in.Source.Authors, Kind: in.Source.Kind,
		URL: in.Source.URL, Licence: "original-summary", LicenceURL: in.Source.URL,
		Attribution: in.Source.Title, RetrievedAt: s.today(),
	}
	card := content.Card{ID: "contribution--01", Topic: in.Topic, Tags: in.Tags, Title: in.Title, Body: in.Body,
		ApplyIt: in.ApplyIt, Quiz: in.Quiz, Health: in.Topic == "health"}
	problems := append(content.ValidateSource("contribution", src), content.ValidateCard("contribution", src, card)...)
	if len(problems) > 0 {
		msgs := make([]string, 0, len(problems))
		for _, p := range problems {
			msgs = append(msgs, strings.TrimPrefix(p.Field, "source.")+" "+p.Message)
		}
		writeError(w, http.StatusBadRequest, "invalid_contribution", strings.Join(msgs, "; "))
		return
	}
	c, err := s.Store.CreateContribution(r.Context(), userID(r), in)
	if err != nil {
		s.fail(w, r, err, "contribution")
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) myContributions(w http.ResponseWriter, r *http.Request) {
	cs, err := s.Store.MyContributions(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "contributions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contributions": cs})
}

func (s *Server) queue(w http.ResponseWriter, r *http.Request) {
	cs, err := s.Store.PendingContributions(r.Context())
	if err != nil {
		s.fail(w, r, err, "contributions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contributions": cs})
}

type noteInput struct {
	Note string `json:"note"`
}

func (s *Server) approve(w http.ResponseWriter, r *http.Request) {
	var in noteInput
	if r.ContentLength != 0 && !decode(w, r, &in) {
		return
	}
	c, err := s.Store.ApproveContribution(r.Context(), r.PathValue("id"), userID(r), in.Note, s.Now())
	if err != nil {
		s.fail(w, r, err, "pending contribution")
		return
	}
	s.Cache.Delete(r.Context(), "topics")
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) reject(w http.ResponseWriter, r *http.Request) {
	var in noteInput
	if !decode(w, r, &in) {
		return
	}
	if strings.TrimSpace(in.Note) == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "a note explaining the rejection is required")
		return
	}
	c, err := s.Store.RejectContribution(r.Context(), r.PathValue("id"), userID(r), in.Note, s.Now())
	if err != nil {
		s.fail(w, r, err, "pending contribution")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// --- agent ---

func (s *Server) chat(w http.ResponseWriter, r *http.Request) {
	if s.Agent == nil {
		writeError(w, http.StatusServiceUnavailable, "agent_unavailable", "the guide is not configured on this server")
		return
	}
	var in struct {
		Messages []agent.Message `json:"messages"`
	}
	if !decode(w, r, &in) {
		return
	}
	limit := s.AgentHourly
	if u, err := s.Store.UserByID(r.Context(), userID(r)); err == nil && u.Premium {
		limit *= premiumAgentFactor
	}
	if !s.Cache.Allow(r.Context(), "agent:"+userID(r)+":"+s.Now().UTC().Format("2006010215"), limit, time.Hour) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "you've reached this hour's question limit")
		return
	}
	reply, err := s.Agent.Chat(r.Context(), in.Messages)
	if errors.Is(err, agent.ErrBadConversation) {
		writeError(w, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	if errors.Is(err, context.Canceled) {
		return
	}
	if err != nil {
		slog.Error("agent chat", "err", err)
		writeError(w, http.StatusBadGateway, "agent_failed", "the guide couldn't answer right now, please try again")
		return
	}
	writeJSON(w, http.StatusOK, reply)
}
