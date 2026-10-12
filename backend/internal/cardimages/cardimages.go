// Package cardimages attaches each card's picture, shown at the top of the full card.
//
// content/images/manifest.json lists, per card id, the picture's path in the media
// store (images/cards/v1/<card-id>.webp, 3:2 WebP), a full-size original, its type
// (illustration, 3d or chart) and a caption. The API reads it at startup
// (CARD_IMAGE_DIR) and adds an "image" object to every card that has one.
package cardimages

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

// Image is the picture attached to a card, as returned by the API.
type Image struct {
	URL     string `json:"url"`
	FullURL string `json:"full_url,omitempty"`
	Type    string `json:"type"` // illustration, 3d or chart
	Caption string `json:"caption"`
	// Basis is set on charts: "data" when they plot real figures (Source names them),
	// "illustration" when they only picture an idea.
	Basis  string `json:"basis,omitempty"`
	Source string `json:"source,omitempty"`
	Credit string `json:"credit,omitempty"`
}

// Set maps card ids to their picture.
type Set map[string]Image

type manifest struct {
	Version int `json:"version"`
	Cards   map[string]struct {
		File    string `json:"file"`
		Full    string `json:"full"`
		Type    string `json:"type"`
		Caption string `json:"caption"`
		Basis   string `json:"basis"`
		Source  string `json:"source"`
		Credit  string `json:"credit"`
	} `json:"cards"`
}

// Load reads dir/manifest.json. A missing folder or manifest is not an error: cards
// simply stay text-only. On local disk a card whose picture was never copied into
// MEDIA_DIR is left out; R2 is not checked at startup.
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
		return nil, fmt.Errorf("card image manifest: %w", err)
	}
	_, local := media.(*objstore.Local)
	for id, e := range m.Cards {
		if e.File == "" {
			continue
		}
		if local {
			if ok, _, err := media.Stat(ctx, e.File); err != nil || !ok {
				continue
			}
		}
		img := Image{URL: media.URL(e.File), Type: e.Type, Caption: e.Caption, Basis: e.Basis, Source: e.Source, Credit: e.Credit}
		if e.Full != "" {
			img.FullURL = media.URL(e.Full)
		}
		set[id] = img
	}
	return set, nil
}
