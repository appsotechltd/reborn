package api

import (
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/appsotechltd/reborn/backend/internal/store"
)

// cardVideo hands out a card's explainer as a file to save or share: shape=tall (9:16, for
// Status, Reels, Shorts and TikTok) or shape=wide (16:9, for YouTube, Facebook, X and LinkedIn).
// The media bucket sends no CORS headers, so the web app fetches the file through here to put it
// in the share sheet.
func (s *Server) cardVideo(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	e := store.ExplainerFor(id)
	if e == nil {
		writeError(w, http.StatusNotFound, "not_found", "this card has no video")
		return
	}
	shape := r.URL.Query().Get("shape")
	src := e.VideoURL
	switch shape {
	case "", "tall":
		shape = "tall"
	case "wide":
		if e.Landscape == nil {
			writeError(w, http.StatusNotFound, "not_found", "this video has no wide cut yet")
			return
		}
		src = e.Landscape.VideoURL
	default:
		writeError(w, http.StatusBadRequest, "bad_request", "shape must be tall or wide")
		return
	}
	// Local media is served by this API itself.
	if strings.HasPrefix(src, "/") {
		http.Redirect(w, r, src, http.StatusFound)
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, src, nil)
	if err != nil {
		s.fail(w, r, err, "video")
		return
	}
	res, err := s.mediaClient().Do(req)
	if err != nil {
		writeError(w, http.StatusBadGateway, "upstream", "couldn't fetch the video")
		return
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		writeError(w, http.StatusBadGateway, "upstream", fmt.Sprintf("the media store answered %d", res.StatusCode))
		return
	}
	h := w.Header()
	h.Set("Content-Type", "video/mp4")
	if res.ContentLength > 0 {
		h.Set("Content-Length", strconv.FormatInt(res.ContentLength, 10))
	}
	h.Set("Content-Disposition", fmt.Sprintf(`attachment; filename="reborn-%s-%s.mp4"`, id, shape))
	h.Set("Cache-Control", "public, max-age=86400")
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, res.Body)
}
