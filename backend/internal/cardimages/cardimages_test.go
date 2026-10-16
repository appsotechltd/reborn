package cardimages

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

const testManifest = `{"version":1,"cards":{
  "meditations-marcus-aurelius--01":{"file":"images/cards/v1/meditations-marcus-aurelius--01.webp","full":"images/cards/v1-full/meditations-marcus-aurelius--01.png","type":"illustration","caption":"A calm morning"},
  "missing--01":{"file":"images/cards/v1/missing--01.webp","type":"chart","caption":"An idea","basis":"illustration"}}}`

func TestLoad(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), []byte(testManifest), 0o644); err != nil {
		t.Fatal(err)
	}
	media := t.TempDir()
	_ = os.MkdirAll(filepath.Join(media, "images", "cards", "v1"), 0o755)
	if err := os.WriteFile(filepath.Join(media, "images", "cards", "v1", "meditations-marcus-aurelius--01.webp"), []byte("webp"), 0o644); err != nil {
		t.Fatal(err)
	}

	set, err := Load(ctx, dir, &objstore.Local{Dir: media, BaseURL: "/media"})
	if err != nil {
		t.Fatal(err)
	}
	img, ok := set["meditations-marcus-aurelius--01"]
	if !ok || len(set) != 1 {
		t.Fatalf("want only the copied card, got %v", set)
	}
	if img.URL != "/media/images/cards/v1/meditations-marcus-aurelius--01.webp" || img.FullURL != "/media/images/cards/v1-full/meditations-marcus-aurelius--01.png" || img.Type != "illustration" || img.Caption != "A calm morning" {
		t.Fatalf("unexpected image %+v", img)
	}

	r2, err := Load(ctx, dir, objstore.NewR2("acct", "bucket", "k", "s", "https://media.example.com/"))
	if err != nil {
		t.Fatal(err)
	}
	if got := r2["missing--01"]; got.URL != "https://media.example.com/images/cards/v1/missing--01.webp" || got.Basis != "illustration" || got.FullURL != "" {
		t.Fatalf("on R2 every listed card is advertised, got %+v", got)
	}

	none, err := Load(ctx, filepath.Join(dir, "nope"), &objstore.Local{Dir: media, BaseURL: "/media"})
	if err != nil || len(none) != 0 {
		t.Fatalf("missing folder should be empty, got %v %v", none, err)
	}
}

func TestLoadPosts(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	m := `{"version":1,"cards":{"aesops-fables--01":{"file":"images/posts/v1/aesops-fables--01.jpg","width":1080,"height":1350,"alt":"A goose"}}}`
	if err := os.WriteFile(filepath.Join(dir, "posts.json"), []byte(m), 0o644); err != nil {
		t.Fatal(err)
	}
	r2 := objstore.NewR2("acct", "bucket", "k", "s", "https://media.example.com/")
	set, err := LoadPosts(ctx, dir, r2)
	if err != nil {
		t.Fatal(err)
	}
	if got := set["aesops-fables--01"]; got.URL != "https://media.example.com/images/posts/v1/aesops-fables--01.jpg" || got.Width != 1080 || got.Height != 1350 || got.Alt != "A goose" {
		t.Fatalf("unexpected post %+v", got)
	}
	// Not copied into MEDIA_DIR: left out locally.
	local, err := LoadPosts(ctx, dir, &objstore.Local{Dir: t.TempDir(), BaseURL: "/media"})
	if err != nil || len(local) != 0 {
		t.Fatalf("want no local posts, got %v %v", local, err)
	}
	none, err := LoadPosts(ctx, filepath.Join(dir, "nope"), r2)
	if err != nil || len(none) != 0 {
		t.Fatalf("missing folder should be empty, got %v %v", none, err)
	}
}
