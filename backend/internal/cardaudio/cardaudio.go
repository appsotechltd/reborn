// Package cardaudio attaches the voiced recording of each card, played by the Listen
// button and Listen mode.
//
// content/audio/render_audio.py voices every card in the voice chosen for its book
// (content/audio/voices.json) and writes the mp3s to one folder along with
// manifest.json, keyed by card id. The files are uploaded to the media store under
// audio/ (`reborn media-upload <folder> audio`): R2 in production, MEDIA_DIR
// locally. The API reads the manifest at startup and adds an "audio" object to every
// card that has one.
package cardaudio

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

// Prefix is where card recordings live in the media store.
const Prefix = "audio/"

// voiceNames are the display names of the approved Kokoro voices.
var voiceNames = map[string]string{
	"af_heart": "Heart", "af_bella": "Bella", "bf_emma": "Emma", "am_michael": "Michael",
	"bm_george": "George", "af_sarah": "Sarah", "af_alloy": "Alloy", "af_nova": "Nova",
	"am_adam": "Adam", "am_echo": "Echo", "am_eric": "Eric", "am_liam": "Liam",
}

// Audio is the recording attached to a card, as returned by the API.
type Audio struct {
	URL       string  `json:"url"`
	DurationS float64 `json:"duration_s"`
	Voice     string  `json:"voice"`
	VoiceName string  `json:"voice_name"`
}

// Set maps card ids to their recording.
type Set map[string]Audio

type manifest struct {
	Version int `json:"version"`
	Cards   map[string]struct {
		File     string  `json:"file"`
		Duration float64 `json:"duration_s"`
		Voice    string  `json:"voice"`
	} `json:"cards"`
}

// Load reads dir/manifest.json. A missing folder or manifest is not an error: cards
// simply have no recording, and the apps fall back to the device's voice. On local
// disk a card whose file was never uploaded is left out; R2 is not checked at startup,
// so upload the files before deploying a new manifest.
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
		return nil, fmt.Errorf("card audio manifest: %w", err)
	}
	_, local := media.(*objstore.Local)
	for id, a := range m.Cards {
		if a.File == "" {
			continue
		}
		key := Prefix + path.Base(a.File)
		if local {
			if ok, _, err := media.Stat(ctx, key); err != nil || !ok {
				continue
			}
		}
		name := voiceNames[a.Voice]
		if name == "" {
			name = a.Voice
		}
		set[id] = Audio{URL: media.URL(key), DurationS: a.Duration, Voice: a.Voice, VoiceName: name}
	}
	return set, nil
}
