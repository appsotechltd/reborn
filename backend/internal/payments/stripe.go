package payments

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Stripe creates Checkout Sessions and verifies webhooks, over Stripe's REST API.
type Stripe struct {
	SecretKey     string
	WebhookSecret string
	BaseURL       string // defaults to https://api.stripe.com
	HTTP          *http.Client
	Now           func() time.Time
}

// CheckoutRequest describes one gift payment.
type CheckoutRequest struct {
	GiftID     string
	Tier       Tier
	PostTitle  string
	SuccessURL string
	CancelURL  string
	Email      string
}

// CreateCheckout starts a hosted Checkout Session and returns its id and URL.
func (s *Stripe) CreateCheckout(ctx context.Context, in CheckoutRequest) (id, checkoutURL string, err error) {
	form := url.Values{
		"mode":                                   {"payment"},
		"success_url":                            {in.SuccessURL},
		"cancel_url":                             {in.CancelURL},
		"client_reference_id":                    {in.GiftID},
		"metadata[gift_id]":                      {in.GiftID},
		"line_items[0][quantity]":                {"1"},
		"line_items[0][price_data][currency]":    {in.Tier.Currency},
		"line_items[0][price_data][unit_amount]": {strconv.Itoa(in.Tier.AmountCents)},
		"line_items[0][price_data][product_data][name]":        {"Reborn gift: " + in.Tier.Name},
		"line_items[0][price_data][product_data][description]": {truncate("Supporting Reborn, on \""+in.PostTitle+"\"", 300)},
	}
	if in.Email != "" {
		form.Set("customer_email", in.Email)
	}
	base := s.BaseURL
	if base == "" {
		base = "https://api.stripe.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1/checkout/sessions", strings.NewReader(form.Encode()))
	if err != nil {
		return "", "", err
	}
	req.SetBasicAuth(s.SecretKey, "")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Idempotency-Key", "gift-"+in.GiftID)
	client := s.HTTP
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("stripe: %s: %s", resp.Status, body)
	}
	var out struct {
		ID  string `json:"id"`
		URL string `json:"url"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", "", err
	}
	return out.ID, out.URL, nil
}

// Event is the part of a Stripe webhook event the API uses.
type Event struct {
	Type string `json:"type"`
	Data struct {
		Object struct {
			ID            string            `json:"id"`
			PaymentStatus string            `json:"payment_status"`
			Metadata      map[string]string `json:"metadata"`
		} `json:"object"`
	} `json:"data"`
}

// webhookTolerance is how old a signed webhook may be.
const webhookTolerance = 5 * time.Minute

// VerifyWebhook checks the Stripe-Signature header and decodes the event.
func (s *Stripe) VerifyWebhook(payload []byte, header string) (Event, error) {
	var ev Event
	var ts int64
	var sigs []string
	for _, part := range strings.Split(header, ",") {
		k, v, _ := strings.Cut(strings.TrimSpace(part), "=")
		switch k {
		case "t":
			ts, _ = strconv.ParseInt(v, 10, 64)
		case "v1":
			sigs = append(sigs, v)
		}
	}
	now := time.Now
	if s.Now != nil {
		now = s.Now
	}
	if ts == 0 || len(sigs) == 0 || s.WebhookSecret == "" {
		return ev, ErrInvalid
	}
	if d := now().Sub(time.Unix(ts, 0)); d > webhookTolerance || d < -webhookTolerance {
		return ev, ErrInvalid
	}
	mac := hmac.New(sha256.New, []byte(s.WebhookSecret))
	fmt.Fprintf(mac, "%d.", ts)
	mac.Write(payload)
	want := mac.Sum(nil)
	ok := false
	for _, sig := range sigs {
		if got, err := hex.DecodeString(sig); err == nil && hmac.Equal(got, want) {
			ok = true
		}
	}
	if !ok {
		return ev, ErrInvalid
	}
	return ev, json.Unmarshal(payload, &ev)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
