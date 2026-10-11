// Package explainers attaches rendered explainer videos to cards.
//
// The renderer in content/explainers writes the videos, posters and captions to
// one folder along with manifest.json, keyed by card id. The files are uploaded to
// the media store under explainers/ (`reborn media-upload <folder> explainers`):
// R2 in production, MEDIA_DIR locally, which the API serves under /media/.
// The API reads the manifest at startup and adds an "explainer" object, with the
// media store's URLs, to every card that has one.
package explainers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

// Prefix is where explainer files live in the media store.
const Prefix = "explainers/"

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
// cards simply have no explainer. Links point at media's copy of each file under
// Prefix. On local disk a card whose video was never uploaded is left out, so the
// apps never get a broken link; R2 is not checked at startup.
func Load(ctx context.Context, dir string, media objstore.Store) (Set, error) {
	set := Set{}
	if dir == "" || media == nil {
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
	url := func(name string) string {
		if name == "" {
			return ""
		}
		return media.URL(Prefix + path.Base(name))
	}
	_, local := media.(*objstore.Local)
	for id, e := range m.Explainers {
		if e.Video == "" {
			continue
		}
		if local {
			if ok, _, err := media.Stat(ctx, Prefix+path.Base(e.Video)); err != nil || !ok {
				continue
			}
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
