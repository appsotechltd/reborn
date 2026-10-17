package api

import (
	"net/http"

	"github.com/appsotechltd/reborn/backend/internal/content"
)

// subjects lists the courses of guides, those in ?topic= when it is set.
func (s *Server) subjects(w http.ResponseWriter, r *http.Request) {
	topic := r.URL.Query().Get("topic")
	if topic != "" && !content.IsTopic(topic) {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown topic")
		return
	}
	sjs, err := s.Store.Subjects(r.Context(), userID(r), topic)
	if err != nil {
		s.fail(w, r, err, "subjects")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"subjects": sjs})
}

func (s *Server) subject(w http.ResponseWriter, r *http.Request) {
	sj, err := s.Store.GetSubject(r.Context(), r.PathValue("id"), userID(r))
	if err != nil {
		s.fail(w, r, err, "subject")
		return
	}
	writeJSON(w, http.StatusOK, sj)
}
