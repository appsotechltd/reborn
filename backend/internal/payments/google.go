package payments

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Google verifies Play in-app purchases with the Android Publisher API,
// signing in as a service account.
type Google struct {
	PackageName    string
	ServiceAccount []byte // the service account's JSON key
	BaseURL        string // defaults to https://androidpublisher.googleapis.com
	HTTP           *http.Client
	Now            func() time.Time
}

// GooglePurchase is the part of a product purchase the API uses.
type GooglePurchase struct {
	OrderID       string `json:"orderId"`
	PurchaseState int    `json:"purchaseState"` // 0 purchased, 1 cancelled, 2 pending
}

// VerifyPurchase confirms that a purchase token is a completed purchase of productID.
func (g *Google) VerifyPurchase(ctx context.Context, productID, token string) (GooglePurchase, error) {
	var p GooglePurchase
	access, err := g.accessToken(ctx)
	if err != nil {
		return p, err
	}
	base := g.BaseURL
	if base == "" {
		base = "https://androidpublisher.googleapis.com"
	}
	u := fmt.Sprintf("%s/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s",
		base, url.PathEscape(g.PackageName), url.PathEscape(productID), url.PathEscape(token))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return p, err
	}
	req.Header.Set("Authorization", "Bearer "+access)
	resp, err := g.client().Do(req)
	if err != nil {
		return p, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusBadRequest {
		return p, ErrInvalid
	}
	if resp.StatusCode != http.StatusOK {
		return p, fmt.Errorf("google play: %s: %s", resp.Status, body)
	}
	if err := json.Unmarshal(body, &p); err != nil {
		return p, err
	}
	if p.PurchaseState != 0 || p.OrderID == "" {
		return p, ErrInvalid
	}
	return p, nil
}

func (g *Google) client() *http.Client {
	if g.HTTP != nil {
		return g.HTTP
	}
	return &http.Client{Timeout: 20 * time.Second}
}

func (g *Google) accessToken(ctx context.Context) (string, error) {
	var sa struct {
		ClientEmail string `json:"client_email"`
		PrivateKey  string `json:"private_key"`
		TokenURI    string `json:"token_uri"`
	}
	if err := json.Unmarshal(g.ServiceAccount, &sa); err != nil {
		return "", fmt.Errorf("google service account: %w", err)
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(sa.PrivateKey))
	if err != nil {
		return "", fmt.Errorf("google service account key: %w", err)
	}
	now := time.Now
	if g.Now != nil {
		now = g.Now
	}
	t := now()
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": sa.ClientEmail, "scope": "https://www.googleapis.com/auth/androidpublisher",
		"aud": sa.TokenURI, "iat": t.Unix(), "exp": t.Add(time.Hour).Unix(),
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
	resp, err := g.client().Do(req)
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
	}
	if err := json.Unmarshal(body, &out); err != nil || out.AccessToken == "" {
		return "", fmt.Errorf("google token: no access token")
	}
	return out.AccessToken, nil
}
