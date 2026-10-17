package api

import (
	"fmt"
	"io"
	"net/http"
	"path"
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
	s.proxyMedia(w, r, src, "video/mp4", fmt.Sprintf("reborn-%s-%s.mp4", id, shape))
}

// cardPicture hands out a card's picture as a file to share (WhatsApp Status, Instagram and the
// rest): its 4:5 image post when it has one (the title is set in it), otherwise its picture at
// full size. Like cardVideo, it exists because the media bucket sends no CORS headers.
func (s *Server) cardPicture(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	src := ""
	if p := store.PostImageFor(id); p != nil {
		src = p.URL
	} else if img := store.ImageFor(id); img != nil {
		src = img.FullURL
		if src == "" {
			src = img.URL
		}
	}
	if src == "" {
		writeError(w, http.StatusNotFound, "not_found", "this card has no picture")
		return
	}
	ext := strings.ToLower(path.Ext(strings.SplitN(src, "?", 2)[0]))
	kind := map[string]string{".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}[ext]
	if kind == "" {
		kind, ext = "image/jpeg", ".jpg"
	}
	s.proxyMedia(w, r, src, kind, fmt.Sprintf("reborn-%s%s", id, ext))
}

// proxyMedia streams the media file at src as an attachment named fileName.
func (s *Server) proxyMedia(w http.ResponseWriter, r *http.Request, src, contentType, fileName string) {
	// Local media is served by this API itself.
	if strings.HasPrefix(src, "/") {
		http.Redirect(w, r, src, http.StatusFound)
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, src, nil)
	if err != nil {
		s.fail(w, r, err, "media")
		return
	}
	res, err := s.mediaClient().Do(req)
	if err != nil {
		writeError(w, http.StatusBadGateway, "upstream", "couldn't fetch the file")
		return
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		writeError(w, http.StatusBadGateway, "upstream", fmt.Sprintf("the media store answered %d", res.StatusCode))
		return
	}
	h := w.Header()
	h.Set("Content-Type", contentType)
	if res.ContentLength > 0 {
		h.Set("Content-Length", strconv.FormatInt(res.ContentLength, 10))
	}
	h.Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, fileName))
	h.Set("Cache-Control", "public, max-age=86400")
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, res.Body)
}
