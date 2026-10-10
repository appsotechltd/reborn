package objstore

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"io"
	"os"
	"path/filepath"
	"testing"
)

type memStore map[string][]byte

func (m memStore) Put(_ context.Context, key, _ string, body io.ReadSeeker, _ int64) error {
	b, err := io.ReadAll(body)
	m[key] = b
	return err
}

func (m memStore) Stat(_ context.Context, key string) (bool, string, error) {
	b, ok := m[key]
	sum := md5.Sum(b)
	return ok, hex.EncodeToString(sum[:]), nil
}

func (m memStore) URL(key string) string { return "https://cdn.test/" + key }

func TestUploadDir(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) {
		p := filepath.Join(dir, name)
		_ = os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("a.mp4", "video")
	write("posters/a.jpg", "image")
	write("notes.txt", "skip me")
	write(".cache/b.mp4", "hidden")

	st := memStore{}
	ctx := context.Background()
	res, err := UploadDir(ctx, st, dir, "/explainers/", nil)
	if err != nil {
		t.Fatal(err)
	}
	if res != (UploadResult{Uploaded: 2, Skipped: 1}) {
		t.Fatalf("first run = %+v", res)
	}
	if string(st["explainers/posters/a.jpg"]) != "image" || st["explainers/.cache/b.mp4"] != nil {
		t.Fatalf("keys = %v", st)
	}

	write("a.mp4", "new video")
	res, err = UploadDir(ctx, st, dir, "explainers", nil)
	if err != nil {
		t.Fatal(err)
	}
	if res != (UploadResult{Uploaded: 1, Unchanged: 1, Skipped: 1}) || string(st["explainers/a.mp4"]) != "new video" {
		t.Fatalf("second run = %+v", res)
	}
}
