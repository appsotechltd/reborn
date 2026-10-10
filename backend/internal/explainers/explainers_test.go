package explainers

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func writeDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	manifest := `{"version":1,"explainers":{
	  "aesops-fables--07":{"video":"aesops-fables--07.mp4","poster":"aesops-fables--07.jpg","captions":"aesops-fables--07.vtt","duration_s":52.1,"width":720,"height":1280,"narrated":false,"kind":"animated"},
	  "missing--01":{"video":"missing--01.mp4","poster":"missing--01.jpg"}}}`
	for name, body := range map[string]string{
		"manifest.json":         manifest,
		"aesops-fables--07.mp4": "fake-mp4-bytes",
		"aesops-fables--07.vtt": "WEBVTT\n",
		"notes.txt":             "not served",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestLoad(t *testing.T) {
	dir := writeDir(t)
	set, err := Load(dir, "")
	if err != nil {
		t.Fatal(err)
	}
	e, ok := set["aesops-fables--07"]
	if !ok || len(set) != 1 {
		t.Fatalf("want only the rendered card, got %v", set)
	}
	if e.VideoURL != "/media/explainers/aesops-fables--07.mp4" || e.CaptionsURL != "/media/explainers/aesops-fables--07.vtt" || e.Kind != "animated" || e.DurationS != 52.1 {
		t.Fatalf("unexpected explainer %+v", e)
	}

	cdn, err := Load(dir, "https://media.example.com/")
	if err != nil {
		t.Fatal(err)
	}
	if got := cdn["missing--01"].VideoURL; got != "https://media.example.com/explainers/missing--01.mp4" {
		t.Fatalf("with a media base URL every listed video is advertised, got %q", got)
	}

	none, err := Load(filepath.Join(dir, "nope"), "")
	if err != nil || len(none) != 0 {
		t.Fatalf("missing folder should be empty, got %v %v", none, err)
	}
}

func TestHandler(t *testing.T) {
	h := Handler(writeDir(t))
	for path, want := range map[string]int{
		"/media/explainers/aesops-fables--07.mp4": http.StatusOK,
		"/media/explainers/aesops-fables--07.vtt": http.StatusOK,
		"/media/explainers/manifest.json":         http.StatusNotFound,
		"/media/explainers/notes.txt":             http.StatusNotFound,
		"/media/explainers/":                      http.StatusNotFound,
		"/media/explainers/../go.mod":             http.StatusNotFound,
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != want {
			t.Errorf("%s: status %d, want %d", path, rec.Code, want)
		}
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/media/explainers/aesops-fables--07.mp4", nil)
	req.Header.Set("Range", "bytes=0-3")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusPartialContent || rec.Body.String() != "fake" || rec.Header().Get("Content-Type") != "video/mp4" {
		t.Fatalf("range request: %d %q %q", rec.Code, rec.Body.String(), rec.Header().Get("Content-Type"))
	}
}
