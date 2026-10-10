package api

import (
	"net/http"
	"net/mail"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/auth"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

type credentials struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var in credentials
	if !decode(w, r, &in) {
		return
	}
	if _, err := mail.ParseAddress(in.Email); err != nil || len(in.Email) > 254 {
		writeError(w, http.StatusBadRequest, "bad_request", "a valid email is required")
		return
	}
	if len(in.Password) < 8 || len(in.Password) > 72 {
		writeError(w, http.StatusBadRequest, "bad_request", "password must be 8-72 characters")
		return
	}
	name := strings.TrimSpace(in.DisplayName)
	if name == "" {
		name = strings.Split(in.Email, "@")[0]
	}
	if utf8.RuneCountInString(name) > 60 {
		writeError(w, http.StatusBadRequest, "bad_request", "display_name must be at most 60 characters")
		return
	}
	hash, err := auth.HashPassword(in.Password)
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	u, err := s.Store.CreateUser(r.Context(), in.Email, hash, name)
	if err == store.ErrConflict {
		writeError(w, http.StatusConflict, "email_taken", "an account with that email already exists")
		return
	}
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	s.issue(w, r, http.StatusCreated, u)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var in credentials
	if !decode(w, r, &in) {
		return
	}
	if !s.Cache.Allow(r.Context(), "login:"+strings.ToLower(in.Email), 10, 15*time.Minute) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "too many attempts, try again later")
		return
	}
	u, hash, err := s.Store.UserByEmail(r.Context(), in.Email)
	if err != nil && err != store.ErrNotFound {
		s.fail(w, r, err, "user")
		return
	}
	if err == store.ErrNotFound || !auth.CheckPassword(hash, in.Password) {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "wrong email or password")
		return
	}
	s.issue(w, r, http.StatusOK, u)
}

func (s *Server) issue(w http.ResponseWriter, r *http.Request, status int, u store.User) {
	tok, err := s.Tokens.Issue(u.ID)
	if err != nil {
		s.fail(w, r, err, "token")
		return
	}
	writeJSON(w, status, map[string]any{"token": tok, "user": u})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) updateMe(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DisplayName *string   `json:"display_name"`
		Topics      *[]string `json:"topics"`
	}
	if !decode(w, r, &in) {
		return
	}
	if in.DisplayName != nil {
		n := strings.TrimSpace(*in.DisplayName)
		if n == "" || utf8.RuneCountInString(n) > 60 {
			writeError(w, http.StatusBadRequest, "bad_request", "display_name must be 1-60 characters")
			return
		}
		in.DisplayName = &n
	}
	var topics []string
	if in.Topics != nil {
		topics = []string{}
		for _, t := range *in.Topics {
			if !content.IsTopic(t) {
				writeError(w, http.StatusBadRequest, "bad_request", "unknown topic "+t)
				return
			}
			topics = append(topics, t)
		}
	}
	u, err := s.Store.UpdateUser(r.Context(), userID(r), in.DisplayName, topics)
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	s.Cache.Delete(r.Context(), "daily:"+s.today()+":"+u.ID)
	writeJSON(w, http.StatusOK, u)
}
