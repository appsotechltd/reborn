package api

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"log/slog"
	"net/http"
	"net/mail"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/auth"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

type credentials struct {
	Email        string `json:"email"`
	Password     string `json:"password"`
	DisplayName  string `json:"display_name"`
	ReferralCode string `json:"referral_code"`
	Timezone     string `json:"timezone"`
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
	referrer := ""
	if in.ReferralCode != "" {
		if referrer, err = s.Store.UserIDByReferralCode(r.Context(), in.ReferralCode); err == store.ErrNotFound {
			referrer = "" // a stale code shouldn't stop anyone signing up
		} else if err != nil {
			s.fail(w, r, err, "user")
			return
		}
	}
	u, err := s.Store.CreateUser(r.Context(), in.Email, hash, name, referrer)
	if err == store.ErrConflict {
		writeError(w, http.StatusConflict, "email_taken", "an account with that email already exists")
		return
	}
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	if in.Timezone != "" {
		if _, terr := time.LoadLocation(in.Timezone); terr == nil {
			tz := in.Timezone
			if u2, uerr := s.Store.UpdateUser(r.Context(), u.ID, store.UserUpdate{Timezone: &tz}); uerr == nil {
				u = u2
			}
		}
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
		DisplayName *string         `json:"display_name"`
		Handle      *string         `json:"handle"`
		Bio         *string         `json:"bio"`
		Topics      *[]string       `json:"topics"`
		Timezone    *string         `json:"timezone"`
		DailyGoal   *int            `json:"daily_goal"`
		Notify      map[string]bool `json:"notify"`
	}
	if !decode(w, r, &in) {
		return
	}
	var up store.UserUpdate
	if in.DisplayName != nil {
		n := strings.TrimSpace(*in.DisplayName)
		if n == "" || utf8.RuneCountInString(n) > 60 {
			writeError(w, http.StatusBadRequest, "bad_request", "display_name must be 1-60 characters")
			return
		}
		up.DisplayName = &n
	}
	if in.Handle != nil {
		h := strings.ToLower(strings.TrimPrefix(strings.TrimSpace(*in.Handle), "@"))
		if !store.HandleRE.MatchString(h) {
			writeError(w, http.StatusBadRequest, "bad_request", "handle must be 3-30 letters, digits or underscores")
			return
		}
		up.Handle = &h
	}
	if in.Bio != nil {
		b := strings.TrimSpace(*in.Bio)
		if utf8.RuneCountInString(b) > 300 {
			writeError(w, http.StatusBadRequest, "bad_request", "bio must be at most 300 characters")
			return
		}
		up.Bio = &b
	}
	if in.Topics != nil {
		up.Topics = []string{}
		for _, t := range *in.Topics {
			if !content.IsTopic(t) {
				writeError(w, http.StatusBadRequest, "bad_request", "unknown topic "+t)
				return
			}
			up.Topics = append(up.Topics, t)
		}
	}
	if in.Timezone != nil {
		if _, err := time.LoadLocation(*in.Timezone); err != nil || *in.Timezone == "" || *in.Timezone == "Local" {
			writeError(w, http.StatusBadRequest, "bad_request", "timezone must be an IANA name like Europe/London")
			return
		}
		up.Timezone = in.Timezone
	}
	if in.DailyGoal != nil {
		if *in.DailyGoal < 1 || *in.DailyGoal > 50 {
			writeError(w, http.StatusBadRequest, "bad_request", "daily_goal must be 1-50")
			return
		}
		up.DailyGoal = in.DailyGoal
	}
	for k := range in.Notify {
		if !slices.Contains(store.NotifyKinds, k) {
			writeError(w, http.StatusBadRequest, "bad_request", "unknown notification setting "+k)
			return
		}
	}
	up.Notify = in.Notify
	u, err := s.Store.UpdateUser(r.Context(), userID(r), up)
	if err == store.ErrHandleTaken {
		writeError(w, http.StatusConflict, "handle_taken", "that handle is taken")
		return
	}
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	s.Cache.Delete(r.Context(), "daily:"+s.today()+":"+u.ID)
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) deleteMe(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DeleteUser(r.Context(), userID(r)); err != nil {
		s.fail(w, r, err, "user")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// resetTTL is how long a password reset link works.
const resetTTL = time.Hour

func hashToken(t string) string {
	sum := sha256.Sum256([]byte(t))
	return hex.EncodeToString(sum[:])
}

// forgotPassword emails a reset link. It answers the same way whether or not
// the account exists, so it can't be used to find out who has signed up.
func (s *Server) forgotPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if !decode(w, r, &in) {
		return
	}
	email := strings.ToLower(strings.TrimSpace(in.Email))
	if _, err := mail.ParseAddress(email); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "a valid email is required")
		return
	}
	if !s.Cache.Allow(r.Context(), "forgot:"+email, 3, time.Hour) || !s.Cache.Allow(r.Context(), "forgot-ip:"+clientIP(r), 20, time.Hour) {
		w.WriteHeader(http.StatusAccepted)
		return
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		s.fail(w, r, err, "reset")
		return
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	u, err := s.Store.CreatePasswordReset(r.Context(), email, hashToken(token), s.Now().Add(resetTTL))
	if err == store.ErrNotFound {
		w.WriteHeader(http.StatusAccepted)
		return
	}
	if err != nil {
		s.fail(w, r, err, "reset")
		return
	}
	link := s.WebBaseURL + "/reset-password?token=" + token
	body := "Hi " + u.DisplayName + ",\n\nSomeone asked to reset the password for your Reborn account. " +
		"If it was you, open this link within an hour to choose a new password:\n\n" + link +
		"\n\nIf it wasn't you, ignore this email and your password stays the same.\n\nReborn"
	if s.Mailer != nil {
		if err := s.Mailer.Send(r.Context(), u.Email, "Reset your Reborn password", body); err != nil {
			slog.Error("send reset email", "err", err)
		}
	}
	w.WriteHeader(http.StatusAccepted)
}

func (s *Server) resetPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if !decode(w, r, &in) {
		return
	}
	if len(in.Password) < 8 || len(in.Password) > 72 {
		writeError(w, http.StatusBadRequest, "bad_request", "password must be 8-72 characters")
		return
	}
	hash, err := auth.HashPassword(in.Password)
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	u, err := s.Store.ResetPassword(r.Context(), hashToken(in.Token), hash, s.Now())
	if err == store.ErrNotFound {
		writeError(w, http.StatusBadRequest, "invalid_token", "this reset link is invalid or has expired")
		return
	}
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	s.issue(w, r, http.StatusOK, u)
}
