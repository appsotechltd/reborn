// Package objstore keeps media files (videos, images, captions, documents) in
// Cloudflare R2 through its S3-compatible API, or on local disk for development.
package objstore

import (
	"context"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// Store saves objects by key and gives their public URL.
type Store interface {
	// Put saves body under key. size is the body's length.
	Put(ctx context.Context, key, contentType string, body io.ReadSeeker, size int64) error
	// Stat reports whether key exists and its ETag (an MD5 hex digest for simple uploads).
	Stat(ctx context.Context, key string) (exists bool, etag string, err error)
	// URL is where clients fetch key.
	URL(key string) string
}

// ErrBadKey means a key is empty or tries to leave the store.
var ErrBadKey = errors.New("invalid object key")

// CleanKey checks a key like "explainers/abc.mp4".
func CleanKey(key string) (string, error) {
	k := strings.TrimPrefix(path.Clean("/"+key), "/")
	if k == "" || k == "." || strings.Contains(key, "..") || strings.HasSuffix(key, "/") {
		return "", ErrBadKey
	}
	return k, nil
}

// MediaTypes are the file types the store accepts and the local route serves.
var MediaTypes = map[string]string{
	".mp4": "video/mp4", ".webm": "video/webm", ".m4a": "audio/mp4", ".mp3": "audio/mpeg",
	".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".gif": "image/gif", ".svg": "image/svg+xml",
	".vtt": "text/vtt; charset=utf-8", ".json": "application/json", ".pdf": "application/pdf",
}

// TypeOf returns the content type for a file name, or "" when it isn't allowed.
func TypeOf(name string) string {
	if t, ok := MediaTypes[strings.ToLower(path.Ext(name))]; ok {
		return t
	}
	return ""
}

// Local keeps objects in a folder, served by Handler at BaseURL.
type Local struct {
	Dir     string
	BaseURL string // e.g. "/media" (resolved against the API) or a full URL
}

// Put writes the object to disk.
func (l *Local) Put(_ context.Context, key, _ string, body io.ReadSeeker, _ int64) error {
	k, err := CleanKey(key)
	if err != nil {
		return err
	}
	dst := filepath.Join(l.Dir, filepath.FromSlash(k))
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".upload-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := io.Copy(tmp, body); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), dst)
}

// Stat reports whether the file exists. Local files have no ETag.
func (l *Local) Stat(_ context.Context, key string) (bool, string, error) {
	k, err := CleanKey(key)
	if err != nil {
		return false, "", err
	}
	_, err = os.Stat(filepath.Join(l.Dir, filepath.FromSlash(k)))
	if errors.Is(err, os.ErrNotExist) {
		return false, "", nil
	}
	return err == nil, "", err
}

// URL joins the base URL and key.
func (l *Local) URL(key string) string { return strings.TrimSuffix(l.BaseURL, "/") + "/" + key }

// Handler serves the folder under prefix, with range requests for video seeking.
// Only MediaTypes are served.
func (l *Local) Handler(prefix string) http.Handler {
	files := http.FileServer(http.Dir(l.Dir))
	return http.StripPrefix(strings.TrimSuffix(prefix, "/"), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := path.Clean(r.URL.Path)
		ct := TypeOf(name)
		if ct == "" || strings.Contains(r.URL.Path, "..") || strings.HasPrefix(path.Base(name), ".") {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", ct)
		w.Header().Set("Cache-Control", "public, max-age=86400")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		files.ServeHTTP(w, r)
	}))
}

func init() {
	// Make sure the standard library agrees on the few types it guesses itself.
	_ = mime.AddExtensionType(".vtt", "text/vtt")
}
