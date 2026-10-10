// Package explainers attaches rendered explainer videos to cards.
//
// The renderer in content/explainers writes the videos, posters and captions to
// one folder along with manifest.json, keyed by card id. The API reads that
// manifest at startup, adds an "explainer" object to every card that has one,
// and serves the files under /media/explainers/ (or points at MEDIA_BASE_URL,
// e.g. a CDN holding a copy of the folder).
package explainers

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// Route is where the API serves the explainer files.
const Route = "/media/explainers/"

// Explainer is the video attached to a card, as returned by the API.
type Explainer struct {
	Kind        string  `json:"kind"` // "animated" now; "film" once realistic films are rendered
	VideoURL    string  `json:"video_url"`
	PosterURL   string  `json:"poster_url"`
	CaptionsURL string  `json:"captions_url,omitempty"`
	DurationS   float64 `json:"duration_s"`
	Width       int     `json:"width"`
	Height      int     `json:"height"`
	Narrated    bool    `json:"narrated"`
}

// Set maps card ids to their explainer.
type Set map[string]Explainer

type manifest struct {
	Version    int `json:"version"`
	Explainers map[string]struct {
		Kind     string  `json:"kind"`
		Video    string  `json:"video"`
		Poster   string  `json:"poster"`
		Captions string  `json:"captions"`
		Duration float64 `json:"duration_s"`
		Width    int     `json:"width"`
		Height   int     `json:"height"`
		Narrated bool    `json:"narrated"`
	} `json:"explainers"`
}

// Load reads dir/manifest.json. A missing folder or manifest is not an error:
// cards simply have no explainer. URLs are baseURL + "/explainers/" + file name; an empty
// baseURL gives paths under Route, which clients resolve against the API URL.
func Load(dir, baseURL string) (Set, error) {
	set := Set{}
	if dir == "" {
		return set, nil
	}
	raw, err := os.ReadFile(filepath.Join(dir, "manifest.json"))
	if errors.Is(err, fs.ErrNotExist) {
		return set, nil
	}
	if err != nil {
		return nil, err
	}
	var m manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, fmt.Errorf("explainer manifest: %w", err)
	}
	// On a CDN (R2), files live under explainers/ in the bucket, matching `reborn media-upload out explainers`.
	base := strings.TrimSuffix(Route, "/")
	if baseURL != "" {
		base = strings.TrimSuffix(baseURL, "/") + "/explainers"
	}
	url := func(name string) string {
		if name == "" {
			return ""
		}
		return base + "/" + path.Base(name)
	}
	for id, e := range m.Explainers {
		if e.Video == "" {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, path.Base(e.Video))); err != nil && baseURL == "" {
			continue // listed but not rendered here: don't advertise a broken link
		}
		kind := e.Kind
		if kind == "" {
			kind = "animated"
		}
		set[id] = Explainer{Kind: kind, VideoURL: url(e.Video), PosterURL: url(e.Poster), CaptionsURL: url(e.Captions),
			DurationS: e.Duration, Width: e.Width, Height: e.Height, Narrated: e.Narrated}
	}
	return set, nil
}

// allowed lists the file types the media route serves; everything else is 404.
var allowed = map[string]string{".mp4": "video/mp4", ".jpg": "image/jpeg", ".vtt": "text/vtt; charset=utf-8"}

// Handler serves the explainer files from dir, with range requests for seeking.
func Handler(dir string) http.Handler {
	files := http.FileServer(http.Dir(dir))
	return http.StripPrefix(strings.TrimSuffix(Route, "/"), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := path.Clean(r.URL.Path)
		ct, ok := allowed[path.Ext(name)]
		if !ok || strings.Count(name, "/") != 1 {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", ct)
		w.Header().Set("Cache-Control", "public, max-age=86400")
		files.ServeHTTP(w, r)
	}))
}
