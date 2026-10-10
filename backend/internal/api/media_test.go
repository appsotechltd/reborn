package api

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
)

func TestLocalMediaRoute(t *testing.T) {
	dir := t.TempDir()
	_ = os.MkdirAll(filepath.Join(dir, "explainers"), 0o755)
	if err := os.WriteFile(filepath.Join(dir, "explainers", "a.mp4"), []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}
	h := (&Server{Media: &objstore.Local{Dir: dir, BaseURL: "/media"}}).Handler()
	for path, want := range map[string]int{
		"/media/explainers/a.mp4": http.StatusOK,
		"/media/explainers/b.mp4": http.StatusNotFound,
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest("GET", path, nil))
		if rec.Code != want {
			t.Errorf("%s = %d, want %d", path, rec.Code, want)
		}
	}
	// Paths that climb out are redirected away from /media, never served.
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/media/../go.mod", nil))
	if rec.Code == http.StatusOK {
		t.Error("served a file outside the media folder")
	}
	// With R2 the API serves no files itself.
	h = (&Server{Media: objstore.NewR2("acct", "bucket", "k", "s", "https://media.test")}).Handler()
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/media/explainers/a.mp4", nil))
	if rec.Code != http.StatusNotFound {
		t.Errorf("R2 mode served a file: %d", rec.Code)
	}
}
