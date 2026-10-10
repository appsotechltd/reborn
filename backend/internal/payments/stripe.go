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
	var out struct {
		ID  string `json:"id"`
		URL string `json:"url"`
	}
	if err := s.post(ctx, "/v1/checkout/sessions", form, "gift-"+in.GiftID, &out); err != nil {
		return "", "", err
	}
	return out.ID, out.URL, nil
}

// Event is the part of a Stripe webhook event the API uses. The object is a
// Checkout Session or a Subscription, depending on the type.
type Event struct {
	Type string `json:"type"`
	Data struct {
		Object EventObject `json:"object"`
	} `json:"data"`
}

// EventObject holds the fields of a Checkout Session or Subscription the API reads.
type EventObject struct {
	ID                string            `json:"id"`
	Mode              string            `json:"mode"`
	PaymentStatus     string            `json:"payment_status"`
	Customer          string            `json:"customer"`
	ClientReferenceID string            `json:"client_reference_id"`
	Metadata          map[string]string `json:"metadata"`
	Status            string            `json:"status"`
	CurrentPeriodEnd  int64             `json:"current_period_end"`
	EndedAt           int64             `json:"ended_at"`
	Items             struct {
		Data []struct {
			CurrentPeriodEnd int64 `json:"current_period_end"`
		} `json:"data"`
	} `json:"items"`
}

// PeriodEnd is when a subscription's paid period ends. Newer API versions put
// it on the subscription items.
func (o EventObject) PeriodEnd() time.Time {
	end := o.CurrentPeriodEnd
	for _, it := range o.Items.Data {
		end = max(end, it.CurrentPeriodEnd)
	}
	return time.Unix(end, 0)
}

// SubscriptionCheckout describes a premium subscription purchase.
type SubscriptionCheckout struct {
	UserID     string
	Email      string
	Customer   string // reuse an existing Stripe customer when known
	PriceID    string
	Plan       string
	SuccessURL string
	CancelURL  string
}

// CreateSubscriptionCheckout starts a Checkout Session for a subscription.
func (s *Stripe) CreateSubscriptionCheckout(ctx context.Context, in SubscriptionCheckout) (string, error) {
	form := url.Values{
		"mode":                                 {"subscription"},
		"success_url":                          {in.SuccessURL},
		"cancel_url":                           {in.CancelURL},
		"client_reference_id":                  {in.UserID},
		"metadata[user_id]":                    {in.UserID},
		"subscription_data[metadata][user_id]": {in.UserID},
		"subscription_data[metadata][plan]":    {in.Plan},
		"line_items[0][price]":                 {in.PriceID},
		"line_items[0][quantity]":              {"1"},
	}
	if in.Customer != "" {
		form.Set("customer", in.Customer)
	} else if in.Email != "" {
		form.Set("customer_email", in.Email)
	}
	var out struct {
		URL string `json:"url"`
	}
	err := s.post(ctx, "/v1/checkout/sessions", form, "", &out)
	return out.URL, err
}

// CreatePortal opens the billing portal, where a customer cancels or changes a subscription.
func (s *Stripe) CreatePortal(ctx context.Context, customer, returnURL string) (string, error) {
	var out struct {
		URL string `json:"url"`
	}
	err := s.post(ctx, "/v1/billing_portal/sessions", url.Values{"customer": {customer}, "return_url": {returnURL}}, "", &out)
	return out.URL, err
}

func (s *Stripe) post(ctx context.Context, path string, form url.Values, idempotencyKey string, out any) error {
	base := s.BaseURL
	if base == "" {
		base = "https://api.stripe.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+path, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.SetBasicAuth(s.SecretKey, "")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if idempotencyKey != "" {
		req.Header.Set("Idempotency-Key", idempotencyKey)
	}
	client := s.HTTP
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("stripe %s: %s: %s", path, resp.Status, body)
	}
	return json.Unmarshal(body, out)
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
