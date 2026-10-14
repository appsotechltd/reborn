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
