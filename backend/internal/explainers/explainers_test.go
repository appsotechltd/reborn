package explainers

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

const testManifest = `{"version":1,"explainers":{
  "aesops-fables--07":{"video":"aesops-fables--07.mp4","poster":"aesops-fables--07.jpg","captions":"aesops-fables--07.vtt","duration_s":52.1,"width":720,"height":1280,"narrated":false,"kind":"animated"},
  "missing--01":{"video":"missing--01.mp4","poster":"missing--01.jpg"}}}`

func TestLoad(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), []byte(testManifest), 0o644); err != nil {
		t.Fatal(err)
	}
	media := t.TempDir()
	_ = os.MkdirAll(filepath.Join(media, "explainers"), 0o755)
	if err := os.WriteFile(filepath.Join(media, "explainers", "aesops-fables--07.mp4"), []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}

	set, err := Load(ctx, dir, &objstore.Local{Dir: media, BaseURL: "/media"})
	if err != nil {
		t.Fatal(err)
	}
	e, ok := set["aesops-fables--07"]
	if !ok || len(set) != 1 {
		t.Fatalf("want only the uploaded card, got %v", set)
	}
	if e.VideoURL != "/media/explainers/aesops-fables--07.mp4" || e.CaptionsURL != "/media/explainers/aesops-fables--07.vtt" || e.Kind != "animated" || e.DurationS != 52.1 {
		t.Fatalf("unexpected explainer %+v", e)
	}

	r2, err := Load(ctx, dir, objstore.NewR2("acct", "bucket", "k", "s", "https://media.example.com/"))
	if err != nil {
		t.Fatal(err)
	}
	if got := r2["missing--01"].VideoURL; got != "https://media.example.com/explainers/missing--01.mp4" {
		t.Fatalf("on R2 every listed video is advertised, got %q", got)
	}

	none, err := Load(ctx, filepath.Join(dir, "nope"), &objstore.Local{Dir: media, BaseURL: "/media"})
	if err != nil || len(none) != 0 {
		t.Fatalf("missing folder should be empty, got %v %v", none, err)
	}
}
