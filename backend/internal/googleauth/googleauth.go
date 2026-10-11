// Package googleauth gets OAuth access tokens for a Google service account.
package googleauth

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ServiceAccount signs in as a service account and caches the access token.
type ServiceAccount struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
	ProjectID   string `json:"project_id"`

	Scope string       `json:"-"`
	HTTP  *http.Client `json:"-"`
	Now   func() time.Time

	mu      sync.Mutex
	token   string
	expires time.Time
}

// Parse reads a service account JSON key.
func Parse(key []byte, scope string) (*ServiceAccount, error) {
	sa := &ServiceAccount{Scope: scope}
	if err := json.Unmarshal(key, sa); err != nil {
		return nil, fmt.Errorf("service account key: %w", err)
	}
	if sa.ClientEmail == "" || sa.PrivateKey == "" || sa.TokenURI == "" {
		return nil, fmt.Errorf("service account key is missing client_email, private_key or token_uri")
	}
	return sa, nil
}

// Client returns the HTTP client to use.
func (sa *ServiceAccount) Client() *http.Client {
	if sa.HTTP != nil {
		return sa.HTTP
	}
	return &http.Client{Timeout: 20 * time.Second}
}

// Token returns a valid access token, refreshing it when it is about to expire.
func (sa *ServiceAccount) Token(ctx context.Context) (string, error) {
	sa.mu.Lock()
	defer sa.mu.Unlock()
	now := time.Now
	if sa.Now != nil {
		now = sa.Now
	}
	t := now()
	if sa.token != "" && t.Before(sa.expires.Add(-time.Minute)) {
		return sa.token, nil
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(sa.PrivateKey))
	if err != nil {
		return "", fmt.Errorf("service account key: %w", err)
	}
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": sa.ClientEmail, "scope": sa.Scope, "aud": sa.TokenURI, "iat": t.Unix(), "exp": t.Add(time.Hour).Unix(),
	}).SignedString(key)
	if err != nil {
		return "", err
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {assertion}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, sa.TokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := sa.Client().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("google token: %s: %s", resp.Status, body)
	}
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &out); err != nil || out.AccessToken == "" {
		return "", fmt.Errorf("google token: no access token")
	}
	if out.ExpiresIn == 0 {
		out.ExpiresIn = 3600
	}
	sa.token, sa.expires = out.AccessToken, t.Add(time.Duration(out.ExpiresIn)*time.Second)
	return sa.token, nil
}
