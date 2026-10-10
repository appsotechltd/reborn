package objstore

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

// R2 stores objects in a Cloudflare R2 bucket over the S3 API (SigV4, path style).
type R2 struct {
	Endpoint  string // https://<account id>.r2.cloudflarestorage.com
	Bucket    string
	AccessKey string
	SecretKey string
	Region    string // "auto" for R2
	PublicURL string // the bucket's public domain or CDN, e.g. https://media.reborn.app
	HTTP      *http.Client
	Now       func() time.Time
}

// NewR2 returns a store for an R2 bucket in the given Cloudflare account.
func NewR2(accountID, bucket, accessKey, secretKey, publicURL string) *R2 {
	return &R2{Endpoint: "https://" + accountID + ".r2.cloudflarestorage.com", Bucket: bucket,
		AccessKey: accessKey, SecretKey: secretKey, Region: "auto", PublicURL: publicURL}
}

// URL is the object's public address.
func (s *R2) URL(key string) string { return strings.TrimSuffix(s.PublicURL, "/") + "/" + key }

func (s *R2) objectURL(key string) string {
	parts := strings.Split(key, "/")
	for i, p := range parts {
		parts[i] = url.PathEscape(p)
	}
	return strings.TrimSuffix(s.Endpoint, "/") + "/" + url.PathEscape(s.Bucket) + "/" + strings.Join(parts, "/")
}

// Put uploads the object in one request.
func (s *R2) Put(ctx context.Context, key, contentType string, body io.ReadSeeker, size int64) error {
	k, err := CleanKey(key)
	if err != nil {
		return err
	}
	h := sha256.New()
	if _, err := io.Copy(h, body); err != nil {
		return err
	}
	if _, err := body.Seek(0, io.SeekStart); err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, s.objectURL(k), io.NopCloser(body))
	if err != nil {
		return err
	}
	req.ContentLength = size
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Cache-Control", "public, max-age=31536000")
	s.sign(req, hex.EncodeToString(h.Sum(nil)))
	resp, err := s.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("r2 put %s: %s: %s", k, resp.Status, msg)
	}
	return nil
}

// Stat checks whether the object exists.
func (s *R2) Stat(ctx context.Context, key string) (bool, string, error) {
	k, err := CleanKey(key)
	if err != nil {
		return false, "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, s.objectURL(k), nil)
	if err != nil {
		return false, "", err
	}
	s.sign(req, emptySHA256)
	resp, err := s.client().Do(req)
	if err != nil {
		return false, "", err
	}
	resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
		return true, strings.Trim(resp.Header.Get("ETag"), `"`), nil
	case http.StatusNotFound:
		return false, "", nil
	default:
		return false, "", fmt.Errorf("r2 head %s: %s", k, resp.Status)
	}
}

func (s *R2) client() *http.Client {
	if s.HTTP != nil {
		return s.HTTP
	}
	return &http.Client{Timeout: 10 * time.Minute}
}

const emptySHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

// sign adds AWS Signature Version 4 headers to req.
func (s *R2) sign(req *http.Request, payloadHash string) {
	now := time.Now
	if s.Now != nil {
		now = s.Now
	}
	t := now().UTC()
	amzDate := t.Format("20060102T150405Z")
	day := t.Format("20060102")
	req.Header.Set("x-amz-date", amzDate)
	req.Header.Set("x-amz-content-sha256", payloadHash)
	req.Header.Set("Authorization", authorization(req, s.AccessKey, s.SecretKey, s.Region, "s3", payloadHash, amzDate, day))
}

// authorization builds the SigV4 Authorization header for the request's
// host, x-amz-* and content headers.
func authorization(req *http.Request, accessKey, secretKey, region, service, payloadHash, amzDate, day string) string {
	headers := map[string]string{"host": req.URL.Host}
	for k, v := range req.Header {
		lk := strings.ToLower(k)
		if strings.HasPrefix(lk, "x-amz-") || lk == "content-type" || lk == "range" || lk == "cache-control" {
			headers[lk] = strings.TrimSpace(strings.Join(v, ","))
		}
	}
	names := make([]string, 0, len(headers))
	for k := range headers {
		names = append(names, k)
	}
	sort.Strings(names)
	var canonHeaders strings.Builder
	for _, k := range names {
		canonHeaders.WriteString(k + ":" + headers[k] + "\n")
	}
	signed := strings.Join(names, ";")
	canonPath := req.URL.EscapedPath()
	if canonPath == "" {
		canonPath = "/"
	}
	canonical := strings.Join([]string{req.Method, canonPath, canonicalQuery(req.URL.Query()), canonHeaders.String(), signed, payloadHash}, "\n")
	scope := day + "/" + region + "/" + service + "/aws4_request"
	sum := sha256.Sum256([]byte(canonical))
	toSign := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + hex.EncodeToString(sum[:])
	key := hmacSHA256([]byte("AWS4"+secretKey), day)
	key = hmacSHA256(key, region)
	key = hmacSHA256(key, service)
	key = hmacSHA256(key, "aws4_request")
	sig := hex.EncodeToString(hmacSHA256(key, toSign))
	return "AWS4-HMAC-SHA256 Credential=" + accessKey + "/" + scope + ", SignedHeaders=" + signed + ", Signature=" + sig
}

func canonicalQuery(q url.Values) string {
	keys := make([]string, 0, len(q))
	for k := range q {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var parts []string
	for _, k := range keys {
		vs := append([]string(nil), q[k]...)
		sort.Strings(vs)
		for _, v := range vs {
			parts = append(parts, awsEscape(k)+"="+awsEscape(v))
		}
	}
	return strings.Join(parts, "&")
}

func awsEscape(s string) string {
	return strings.ReplaceAll(url.QueryEscape(s), "+", "%20")
}

func hmacSHA256(key []byte, data string) []byte {
	m := hmac.New(sha256.New, key)
	m.Write([]byte(data))
	return m.Sum(nil)
}
