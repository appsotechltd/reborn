package payments

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/googleauth"
)

// Google verifies Play in-app purchases with the Android Publisher API,
// signing in as a service account.
type Google struct {
	PackageName    string
	ServiceAccount []byte // the service account's JSON key
	BaseURL        string // defaults to https://androidpublisher.googleapis.com
	HTTP           *http.Client
	Now            func() time.Time

	once  sync.Once
	sa    *googleauth.ServiceAccount
	saErr error
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
	g.once.Do(func() {
		g.sa, g.saErr = googleauth.Parse(g.ServiceAccount, "https://www.googleapis.com/auth/androidpublisher")
		if g.sa != nil {
			g.sa.HTTP, g.sa.Now = g.HTTP, g.Now
		}
	})
	if g.saErr != nil {
		return "", g.saErr
	}
	return g.sa.Token(ctx)
}

// GoogleSubscription is the part of a subscription purchase the API uses.
type GoogleSubscription struct {
	ProductID string
	State     string // SUBSCRIPTION_STATE_ACTIVE, _CANCELED, _IN_GRACE_PERIOD, _ON_HOLD, _PAUSED, _EXPIRED
	Expires   time.Time
	AccountID string // obfuscatedExternalAccountId, which the app sets to the user's id
}

// VerifySubscription reads a subscription purchase token's current state.
func (g *Google) VerifySubscription(ctx context.Context, token string) (GoogleSubscription, error) {
	var sub GoogleSubscription
	access, err := g.accessToken(ctx)
	if err != nil {
		return sub, err
	}
	base := g.BaseURL
	if base == "" {
		base = "https://androidpublisher.googleapis.com"
	}
	u := fmt.Sprintf("%s/androidpublisher/v3/applications/%s/purchases/subscriptionsv2/tokens/%s",
		base, url.PathEscape(g.PackageName), url.PathEscape(token))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return sub, err
	}
	req.Header.Set("Authorization", "Bearer "+access)
	resp, err := g.client().Do(req)
	if err != nil {
		return sub, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusBadRequest {
		return sub, ErrInvalid
	}
	if resp.StatusCode != http.StatusOK {
		return sub, fmt.Errorf("google play: %s: %s", resp.Status, body)
	}
	var out struct {
		SubscriptionState string `json:"subscriptionState"`
		LineItems         []struct {
			ProductID  string    `json:"productId"`
			ExpiryTime time.Time `json:"expiryTime"`
		} `json:"lineItems"`
		ExternalAccountIdentifiers struct {
			ObfuscatedExternalAccountID string `json:"obfuscatedExternalAccountId"`
		} `json:"externalAccountIdentifiers"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return sub, err
	}
	if len(out.LineItems) == 0 {
		return sub, ErrInvalid
	}
	sub.State, sub.AccountID = out.SubscriptionState, out.ExternalAccountIdentifiers.ObfuscatedExternalAccountID
	for _, li := range out.LineItems {
		if li.ExpiryTime.After(sub.Expires) {
			sub.Expires, sub.ProductID = li.ExpiryTime, li.ProductID
		}
	}
	return sub, nil
}
