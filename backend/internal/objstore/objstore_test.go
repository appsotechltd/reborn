package objstore

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The example from AWS's "Signature Version 4: GET object" documentation.
func TestSigV4KnownAnswer(t *testing.T) {
	req, _ := http.NewRequest("GET", "https://examplebucket.s3.amazonaws.com/test.txt", nil)
	req.Header.Set("Range", "bytes=0-9")
	req.Header.Set("x-amz-content-sha256", emptySHA256)
	req.Header.Set("x-amz-date", "20130524T000000Z")
	got := authorization(req, "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "us-east-1", "s3",
		emptySHA256, "20130524T000000Z", "20130524")
	want := "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " +
		"SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, " +
		"Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
	if got != want {
		t.Fatalf("got  %s\nwant %s", got, want)
	}
}

func TestR2PutAndStat(t *testing.T) {
	stored := map[string][]byte{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.Header.Get("Authorization"), "AWS4-HMAC-SHA256 Credential=key/") || r.Header.Get("x-amz-content-sha256") == "" {
			http.Error(w, "unsigned", 403)
			return
		}
		switch r.Method {
		case "PUT":
			b, _ := io.ReadAll(r.Body)
			if int64(len(b)) != r.ContentLength || r.Header.Get("Content-Type") != "video/mp4" {
				http.Error(w, "bad", 400)
				return
			}
			stored[r.URL.Path] = b
		case "HEAD":
			if _, ok := stored[r.URL.Path]; !ok {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("ETag", `"abc"`)
		}
	}))
	defer srv.Close()
	s := &R2{Endpoint: srv.URL, Bucket: "media", AccessKey: "key", SecretKey: "secret", Region: "auto",
		PublicURL: "https://media.reborn.test/", Now: func() time.Time { return time.Unix(1_800_000_000, 0) }}
	ctx := context.Background()
	if ok, _, err := s.Stat(ctx, "explainers/a b.mp4"); ok || err != nil {
		t.Fatalf("stat before put = %v, %v", ok, err)
	}
	body := []byte("fake video")
	if err := s.Put(ctx, "explainers/a b.mp4", "video/mp4", bytes.NewReader(body), int64(len(body))); err != nil {
		t.Fatal(err)
	}
	if string(stored["/media/explainers/a b.mp4"]) != "fake video" {
		t.Fatalf("stored = %v", stored)
	}
	if ok, etag, err := s.Stat(ctx, "explainers/a b.mp4"); !ok || etag != "abc" || err != nil {
		t.Fatalf("stat = %v %q %v", ok, etag, err)
	}
	if u := s.URL("explainers/x.mp4"); u != "https://media.reborn.test/explainers/x.mp4" {
		t.Fatalf("url = %s", u)
	}
	if err := s.Put(ctx, "../etc/passwd", "video/mp4", bytes.NewReader(body), 4); err != ErrBadKey {
		t.Fatalf("bad key err = %v", err)
	}
}

func TestLocal(t *testing.T) {
	dir := t.TempDir()
	l := &Local{Dir: dir, BaseURL: "/media"}
	ctx := context.Background()
	if err := l.Put(ctx, "explainers/a.mp4", "video/mp4", strings.NewReader("vid"), 3); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "explainers", "a.mp4")); string(b) != "vid" {
		t.Fatalf("file = %q", b)
	}
	if ok, _, _ := l.Stat(ctx, "explainers/a.mp4"); !ok {
		t.Fatal("stat missed the file")
	}
	_ = os.WriteFile(filepath.Join(dir, "secret.env"), []byte("x"), 0o644)
	srv := httptest.NewServer(l.Handler("/media/"))
	defer srv.Close()
	resp, _ := http.Get(srv.URL + "/media/explainers/a.mp4")
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || string(b) != "vid" || resp.Header.Get("Content-Type") != "video/mp4" {
		t.Fatalf("serve = %d %q %s", resp.StatusCode, b, resp.Header.Get("Content-Type"))
	}
	if resp, _ := http.Get(srv.URL + "/media/secret.env"); resp.StatusCode != 404 {
		t.Fatalf("served a non-media file: %d", resp.StatusCode)
	}
	if l.URL("explainers/a.mp4") != "/media/explainers/a.mp4" {
		t.Fatal(l.URL("explainers/a.mp4"))
	}
}
