package cardaudio

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

const testManifest = `{"version":1,"engine":"kokoro-82m@1.0","cards":{
  "moral-letters-seneca--01":{"file":"moral-letters-seneca--01.mp3","duration_s":41.2,"voice":"bm_george","hash":"x"},
  "missing--01":{"file":"missing--01.mp3","duration_s":30,"voice":"af_heart"}}}`

func TestLoad(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), []byte(testManifest), 0o644); err != nil {
		t.Fatal(err)
	}
	media := t.TempDir()
	_ = os.MkdirAll(filepath.Join(media, "audio"), 0o755)
	if err := os.WriteFile(filepath.Join(media, "audio", "moral-letters-seneca--01.mp3"), []byte("mp3"), 0o644); err != nil {
		t.Fatal(err)
	}

	set, err := Load(ctx, dir, &objstore.Local{Dir: media, BaseURL: "/media"})
	if err != nil {
		t.Fatal(err)
	}
	a, ok := set["moral-letters-seneca--01"]
	if !ok || len(set) != 1 {
		t.Fatalf("want only the uploaded card, got %v", set)
	}
	if a.URL != "/media/audio/moral-letters-seneca--01.mp3" || a.DurationS != 41.2 || a.Voice != "bm_george" || a.VoiceName != "George" {
		t.Fatalf("unexpected audio %+v", a)
	}

	r2, err := Load(ctx, dir, objstore.NewR2("acct", "bucket", "k", "s", "https://media.example.com/"))
	if err != nil {
		t.Fatal(err)
	}
	if got := r2["missing--01"]; got.URL != "https://media.example.com/audio/missing--01.mp3" || got.VoiceName != "Heart" {
		t.Fatalf("on R2 every listed card is advertised, got %+v", got)
	}

	none, err := Load(ctx, filepath.Join(dir, "nope"), &objstore.Local{Dir: media, BaseURL: "/media"})
	if err != nil || len(none) != 0 {
		t.Fatalf("missing folder should be empty, got %v %v", none, err)
	}
}
