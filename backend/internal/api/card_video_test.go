package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/cardimages"
	"github.com/appsotechltd/reborn/backend/internal/explainers"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

func TestCardVideoDownload(t *testing.T) {
	media := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/explainers/a--01.mp4":
			_, _ = io.WriteString(w, "tall video")
		case "/explainers/a--01-wide.mp4":
			_, _ = io.WriteString(w, "wide video")
		default:
			http.NotFound(w, r)
		}
	}))
	defer media.Close()
	store.SetExplainers(explainers.Set{
		"a--01": {VideoURL: media.URL + "/explainers/a--01.mp4",
			Landscape: &explainers.Cut{VideoURL: media.URL + "/explainers/a--01-wide.mp4", Width: 1280, Height: 720}},
		"b--01": {VideoURL: media.URL + "/explainers/b--01.mp4"},
		"c--01": {VideoURL: "/media/explainers/c--01.mp4"},
	})
	t.Cleanup(func() { store.SetExplainers(nil) })
	h := (&Server{}).Handler()

	get := func(path string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		return rec
	}
	for _, c := range []struct{ path, body, name string }{
		{"/v1/cards/a--01/video", "tall video", "reborn-a--01-tall.mp4"},
		{"/v1/cards/a--01/video?shape=wide", "wide video", "reborn-a--01-wide.mp4"},
	} {
		rec := get(c.path)
		if rec.Code != http.StatusOK || rec.Body.String() != c.body || rec.Header().Get("Content-Type") != "video/mp4" {
			t.Fatalf("%s: got %d %q %v", c.path, rec.Code, rec.Body.String(), rec.Header())
		}
		if want := `attachment; filename="` + c.name + `"`; rec.Header().Get("Content-Disposition") != want {
			t.Fatalf("%s: disposition %q", c.path, rec.Header().Get("Content-Disposition"))
		}
	}
	for path, want := range map[string]int{
		"/v1/cards/b--01/video?shape=wide": http.StatusNotFound,   // no wide cut yet
		"/v1/cards/b--01/video":            http.StatusBadGateway, // the file is missing upstream
		"/v1/cards/a--01/video?shape=huge": http.StatusBadRequest,
		"/v1/cards/zzz--01/video":          http.StatusNotFound,
		"/v1/cards/c--01/video":            http.StatusFound, // local media: served by the API itself
	} {
		if rec := get(path); rec.Code != want {
			t.Fatalf("%s: got %d, want %d", path, rec.Code, want)
		}
	}
}

func TestCardPictureDownload(t *testing.T) {
	media := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/images/posts/v1/a--01.jpg":
			_, _ = io.WriteString(w, "post")
		case "/images/cards/v1-full/b--01.png":
			_, _ = io.WriteString(w, "full")
		default:
			http.NotFound(w, r)
		}
	}))
	defer media.Close()
	store.SetPostImages(cardimages.Posts{"a--01": {URL: media.URL + "/images/posts/v1/a--01.jpg", Width: 1080, Height: 1350}})
	store.SetImages(cardimages.Set{
		"a--01": {URL: media.URL + "/images/cards/v1/a--01.webp"},
		"b--01": {URL: media.URL + "/images/cards/v1/b--01.webp", FullURL: media.URL + "/images/cards/v1-full/b--01.png"},
		"c--01": {URL: media.URL + "/images/cards/v1/c--01.webp"},
	})
	t.Cleanup(func() { store.SetPostImages(nil); store.SetImages(nil) })
	h := (&Server{}).Handler()

	get := func(path string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		return rec
	}
	for _, c := range []struct{ path, body, kind, name string }{
		{"/v1/cards/a--01/picture", "post", "image/jpeg", "reborn-a--01.jpg"}, // the image post wins
		{"/v1/cards/b--01/picture", "full", "image/png", "reborn-b--01.png"},  // else the full-size picture
	} {
		rec := get(c.path)
		if rec.Code != http.StatusOK || rec.Body.String() != c.body || rec.Header().Get("Content-Type") != c.kind {
			t.Fatalf("%s: got %d %q %v", c.path, rec.Code, rec.Body.String(), rec.Header())
		}
		if want := `attachment; filename="` + c.name + `"`; rec.Header().Get("Content-Disposition") != want {
			t.Fatalf("%s: disposition %q", c.path, rec.Header().Get("Content-Disposition"))
		}
	}
	for path, want := range map[string]int{
		"/v1/cards/c--01/picture":   http.StatusBadGateway, // the file is missing upstream
		"/v1/cards/zzz--01/picture": http.StatusNotFound,
	} {
		if rec := get(path); rec.Code != want {
			t.Fatalf("%s: got %d, want %d", path, rec.Code, want)
		}
	}
}
