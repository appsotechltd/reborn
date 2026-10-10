package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/push"
)

type fakePush struct {
	mu   sync.Mutex
	sent map[string][]push.Message
}

func (f *fakePush) Send(_ context.Context, token string, m push.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if token == "dead" {
		return push.ErrUnregistered
	}
	if f.sent == nil {
		f.sent = map[string][]push.Message{}
	}
	f.sent[token] = append(f.sent[token], m)
	return nil
}

func (f *fakePush) count(token string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.sent[token])
}

// eventually retries check until it passes or a couple of seconds go by,
// for work the API does in the background.
func eventually(t *testing.T, check func() bool) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if check() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("condition never became true")
}

func TestNotificationsAndBlocking(t *testing.T) {
	h := setup(t)
	fp := &fakePush{}
	h.api.Push = fp
	ada, _ := h.registerAs("ada@example.com", "Ada")
	bob, bobHandle := h.registerAs("bob@example.com", "Bob")
	adaID := h.do("GET", "/v1/me", ada, nil, 200)["id"].(string)
	bobID := h.do("GET", "/v1/users/"+bobHandle, ada, nil, 200)["id"].(string)

	h.do("POST", "/v1/devices", ada, map[string]any{"platform": "ios", "token": "ada-phone"}, 204)
	h.do("POST", "/v1/devices", ada, map[string]any{"platform": "android", "token": "dead"}, 204)
	h.do("POST", "/v1/devices", ada, map[string]any{"platform": "fax", "token": "x"}, 400)

	// Bob follows Ada and replies to her comment: she gets both, in the inbox and as pushes.
	h.do("PUT", "/v1/follows/user/"+adaID, bob, nil, 200)
	c := h.do("POST", "/v1/posts/nhs-sleep-tips--01/comments", ada, map[string]any{"body": "Helpful"}, 201)
	h.do("POST", "/v1/posts/nhs-sleep-tips--01/comments", bob, map[string]any{"body": "Agreed", "parent_id": c["id"]}, 201)
	h.do("POST", "/v1/posts/nhs-sleep-tips--01/comments", ada, map[string]any{"body": "Thanks", "parent_id": c["id"]}, 201) // own thread: no self-notification
	var inbox map[string]any
	eventually(t, func() bool {
		inbox = h.do("GET", "/v1/notifications", ada, nil, 200)
		return len(list(inbox, "notifications")) == 2 && fp.count("ada-phone") == 2
	})
	if inbox["unread"].(float64) != 2 {
		t.Fatalf("unread = %v", inbox["unread"])
	}
	kinds := map[string]bool{}
	for _, n := range list(inbox, "notifications") {
		kinds[n.(map[string]any)["kind"].(string)] = true
	}
	if !kinds["follow"] || !kinds["reply"] {
		t.Fatalf("kinds = %v", kinds)
	}
	eventually(t, func() bool {
		var n int
		_ = h.st.DB.QueryRow(context.Background(), `SELECT count(*) FROM devices WHERE token = 'dead'`).Scan(&n)
		return n == 0
	})
	h.do("POST", "/v1/notifications/read", ada, nil, 204)
	if n := h.do("GET", "/v1/notifications", ada, nil, 200)["unread"].(float64); n != 0 {
		t.Fatalf("unread after read = %v", n)
	}

	// Turning replies off stops the push but keeps the inbox entry.
	h.do("PATCH", "/v1/me", ada, map[string]any{"notify": map[string]bool{"replies": false}}, 200)
	h.do("PATCH", "/v1/me", ada, map[string]any{"notify": map[string]bool{"shouting": true}}, 400)
	h.do("POST", "/v1/posts/nhs-sleep-tips--01/comments", bob, map[string]any{"body": "One more", "parent_id": c["id"]}, 201)
	eventually(t, func() bool { return len(list(h.do("GET", "/v1/notifications", ada, nil, 200), "notifications")) == 3 })
	time.Sleep(50 * time.Millisecond)
	if fp.count("ada-phone") != 2 {
		t.Fatalf("push sent despite the setting: %d", fp.count("ada-phone"))
	}

	// Muting hides Bob's comments from Ada only.
	h.do("PUT", "/v1/blocks/"+bobID, ada, map[string]any{"kind": "mute"}, 204)
	if n := len(list(h.do("GET", "/v1/posts/nhs-sleep-tips--01/comments", ada, nil, 200), "comments")); n != 2 {
		t.Fatalf("Ada sees %d comments after muting", n)
	}
	if n := len(list(h.do("GET", "/v1/posts/nhs-sleep-tips--01/comments", "", nil, 200), "comments")); n != 4 {
		t.Fatalf("others see %d comments", n)
	}
	// Blocking also removes follows and stops Bob replying, following or seeing her profile.
	h.do("PUT", "/v1/blocks/"+bobID, ada, map[string]any{"kind": "block"}, 204)
	if n := h.do("GET", "/v1/users/"+bobHandle, ada, nil, 200)["following"].(float64); n != 0 {
		t.Fatalf("follow survived the block: %v", n)
	}
	h.do("POST", "/v1/posts/nhs-sleep-tips--01/comments", bob, map[string]any{"body": "Hey", "parent_id": c["id"]}, 403)
	h.do("PUT", "/v1/follows/user/"+adaID, bob, nil, 404)
	adaHandle := h.do("GET", "/v1/me", ada, nil, 200)["handle"].(string)
	h.do("GET", "/v1/users/"+adaHandle, bob, nil, 404)
	if b := list(h.do("GET", "/v1/me/blocks", ada, nil, 200), "blocks"); len(b) != 1 || b[0].(map[string]any)["kind"] != "block" {
		t.Fatalf("blocks = %v", b)
	}
	h.do("PUT", "/v1/blocks/"+adaID, ada, map[string]any{"kind": "block"}, 400)
	h.do("DELETE", "/v1/blocks/"+bobID, ada, nil, 204)
	h.do("PUT", "/v1/follows/user/"+adaID, bob, nil, 200)
}

func TestDailyPush(t *testing.T) {
	h := setup(t)
	fp := &fakePush{}
	h.api.Push = fp
	ada, _ := h.registerAs("ada@example.com", "Ada")
	h.do("PATCH", "/v1/me", ada, map[string]any{"timezone": "America/New_York"}, 200)
	h.do("PATCH", "/v1/me", ada, map[string]any{"timezone": "Mars/Olympus"}, 400)
	h.do("POST", "/v1/devices", ada, map[string]any{"platform": "android", "token": "ada-phone"}, 204)

	h.now = time.Date(2026, 10, 10, 11, 0, 0, 0, time.UTC) // 7am in New York
	h.api.sendDailyPushes(context.Background())
	if fp.count("ada-phone") != 0 {
		t.Fatal("pushed before 8am local time")
	}
	h.now = time.Date(2026, 10, 10, 12, 30, 0, 0, time.UTC) // 8:30am
	h.api.sendDailyPushes(context.Background())
	h.api.sendDailyPushes(context.Background())
	if fp.count("ada-phone") != 1 {
		t.Fatalf("daily pushes = %d, want 1", fp.count("ada-phone"))
	}
	n := list(h.do("GET", "/v1/notifications", ada, nil, 200), "notifications")
	if len(n) != 1 || n[0].(map[string]any)["kind"] != "daily" || n[0].(map[string]any)["post_id"] == nil {
		t.Fatalf("inbox = %v", n)
	}
	h.now = h.now.Add(24 * time.Hour)
	h.api.sendDailyPushes(context.Background())
	if fp.count("ada-phone") != 2 {
		t.Fatalf("next day's push missing: %d", fp.count("ada-phone"))
	}
}

func TestStreaksAndReferrals(t *testing.T) {
	h := setup(t)
	ada, _ := h.registerAs("ada@example.com", "Ada")
	h.do("PATCH", "/v1/me", ada, map[string]any{"daily_goal": 2}, 200)
	h.do("PATCH", "/v1/me", ada, map[string]any{"daily_goal": 0}, 400)
	ref := h.do("GET", "/v1/me/referrals", ada, nil, 200)
	code := ref["code"].(string)
	if len(code) != 8 || ref["invited"].(float64) != 0 {
		t.Fatalf("referrals = %v", ref)
	}

	out := h.do("POST", "/v1/auth/register", "", map[string]any{"email": "bob@example.com", "password": "password1",
		"display_name": "Bob", "referral_code": code, "timezone": "Europe/London"}, 201)
	bob := out["token"].(string)
	if u := out["user"].(map[string]any); u["timezone"] != "Europe/London" || u["premium"] != false {
		t.Fatalf("bob = %v", u)
	}
	h.do("POST", "/v1/auth/register", "", map[string]any{"email": "cy@example.com", "password": "password1", "referral_code": "NOPE1234"}, 201)

	read := func(tok string, ids ...string) {
		h.do("POST", "/v1/seen", tok, map[string]any{"post_ids": ids}, 204)
	}
	// Ada reads two ideas on three days in a row (the goal is 2), skipping none.
	day := h.now
	for i, pair := range [][]string{{"nhs-sleep-tips--01", "nhs-sleep-tips--02"}, {"nhs-sleep-tips--03", "fixture-psychology-notes--01"}, {"fixture-psychology-notes--02", "fixture-psychology-notes--03"}} {
		h.now = day.AddDate(0, 0, i)
		read(ada, pair...)
	}
	read(ada, "nhs-sleep-tips--01") // already seen: doesn't count twice
	st := h.do("GET", "/v1/me/streak", ada, nil, 200)
	if st["current"].(float64) != 3 || st["longest"].(float64) != 3 || st["today"].(float64) != 2 || st["goal_met"] != true || len(list(st, "last_days")) != 7 {
		t.Fatalf("streak = %v", st)
	}
	// The next day the streak is still alive until the day ends.
	h.now = day.AddDate(0, 0, 3)
	if st := h.do("GET", "/v1/me/streak", ada, nil, 200); st["current"].(float64) != 3 || st["goal_met"] != false {
		t.Fatalf("streak next morning = %v", st)
	}
	h.now = day.AddDate(0, 0, 5)
	if st := h.do("GET", "/v1/me/streak", ada, nil, 200); st["current"].(float64) != 0 || st["longest"].(float64) != 3 {
		t.Fatalf("broken streak = %v", st)
	}

	// Bob's referral pays out on his third active day, to both of them.
	for i := 0; i < 3; i++ {
		h.now = day.AddDate(0, 0, 10+i)
		if i == 2 && h.do("GET", "/v1/me", bob, nil, 200)["premium"] == true {
			t.Fatal("reward came too early")
		}
		read(bob, []string{"meditations-marcus-aurelius--01", "meditations-marcus-aurelius--02", "meditations-marcus-aurelius--03"}[i])
	}
	// Premium is computed against the database clock, so check the dates.
	bobMe := h.do("GET", "/v1/me", bob, nil, 200)
	adaMe := h.do("GET", "/v1/me", ada, nil, 200)
	if bobMe["premium_until"] == nil || adaMe["premium_until"] == nil {
		t.Fatalf("rewards missing: bob %v, ada %v", bobMe["premium_until"], adaMe["premium_until"])
	}
	if r := h.do("GET", "/v1/me/referrals", ada, nil, 200); r["invited"].(float64) != 1 || r["rewarded"].(float64) != 1 {
		t.Fatalf("referrals = %v", r)
	}
	eventually(t, func() bool {
		for _, n := range list(h.do("GET", "/v1/notifications", ada, nil, 200), "notifications") {
			if n.(map[string]any)["kind"] == "reward" {
				return true
			}
		}
		return false
	})
}

func TestDiscoverStashesAndCircles(t *testing.T) {
	h := setup(t)
	ada, adaHandle := h.registerAs("ada@example.com", "Ada")
	bob, _ := h.registerAs("bob@example.com", "Bob")

	h.do("PUT", "/v1/posts/meditations-marcus-aurelius--02/reaction", ada, map[string]any{"kind": "love"}, 204)
	h.do("POST", "/v1/posts/meditations-marcus-aurelius--02/share", bob, map[string]any{"channel": "x"}, 204)
	h.do("PUT", "/v1/posts/nhs-sleep-tips--03/favorite", bob, nil, 204)
	tr := postIDsOf(posts(h.do("GET", "/v1/trending", "", nil, 200)))
	if len(tr) != 2 || tr[0] != "meditations-marcus-aurelius--02" {
		t.Fatalf("trending = %v", tr)
	}
	if n := len(posts(h.do("GET", "/v1/trending?topic=health", "", nil, 200))); n != 1 {
		t.Fatalf("health trending = %d", n)
	}
	h.do("PUT", "/v1/follows/author/"+url.PathEscape("Marcus Aurelius"), ada, nil, 200)
	d := h.do("GET", "/v1/discover", ada, nil, 200)
	authors := list(d, "authors")
	if len(list(d, "trending")) != 2 || len(list(d, "new")) == 0 || len(list(d, "books")) != 3 ||
		authors[0].(map[string]any)["name"] != "Marcus Aurelius" || authors[0].(map[string]any)["followers"].(float64) != 1 {
		t.Fatalf("discover = %v", d)
	}

	// Public stashes.
	st := h.do("POST", "/v1/stashes", ada, map[string]any{"name": "Calm", "is_public": true}, 201)
	if st["is_public"] != true {
		t.Fatalf("stash = %v", st)
	}
	h.do("PUT", "/v1/stashes/"+st["id"].(string)+"/cards/meditations-marcus-aurelius--01", ada, nil, 204)
	priv := h.do("POST", "/v1/stashes", ada, map[string]any{"name": "Private"}, 201)
	pub := h.do("GET", "/v1/public/stashes/"+st["id"].(string), "", nil, 200)
	if len(list(pub, "cards")) != 1 || pub["stash"].(map[string]any)["owner"].(map[string]any)["handle"] != adaHandle {
		t.Fatalf("public stash = %v", pub)
	}
	h.do("GET", "/v1/public/stashes/"+priv["id"].(string), "", nil, 404)
	if n := len(list(h.do("GET", "/v1/users/"+adaHandle+"/stashes", "", nil, 200), "stashes")); n != 1 {
		t.Fatalf("profile stashes = %d", n)
	}
	h.do("PATCH", "/v1/stashes/"+st["id"].(string), ada, map[string]any{"is_public": false}, 200)
	h.do("GET", "/v1/public/stashes/"+st["id"].(string), "", nil, 404)

	// Circles.
	h.do("POST", "/v1/circles", ada, map[string]any{"source_id": "nope", "name": "x"}, 404)
	c := h.do("POST", "/v1/circles", ada, map[string]any{"source_id": "meditations-marcus-aurelius", "name": "Stoic mornings"}, 201)
	id := c["id"].(string)
	if c["is_member"] != true || c["role"] != "owner" || c["members"].(float64) != 1 {
		t.Fatalf("circle = %v", c)
	}
	h.do("GET", "/v1/circles/"+id+"/messages", bob, nil, 404) // not a member
	if j := h.do("POST", "/v1/circles/"+id+"/join", bob, nil, 200); j["members"].(float64) != 2 || j["role"] != "member" {
		t.Fatalf("joined = %v", j)
	}
	if ms := list(h.do("GET", "/v1/circles/"+id+"/members", "", nil, 200), "members"); len(ms) != 2 || ms[0].(map[string]any)["role"] != "owner" || ms[1].(map[string]any)["display_name"] != "Bob" {
		t.Fatalf("members = %v", ms)
	}
	m := h.do("POST", "/v1/circles/"+id+"/messages", bob, map[string]any{"body": "Book II hit hard", "post_id": "meditations-marcus-aurelius--01"}, 201)
	h.do("POST", "/v1/circles/"+id+"/messages", bob, map[string]any{"body": "x", "post_id": "nhs-sleep-tips--01"}, 404) // another book's idea
	h.do("POST", "/v1/circles/"+id+"/messages", ada, map[string]any{"body": "Same"}, 201)
	if msgs := list(h.do("GET", "/v1/circles/"+id+"/messages", ada, nil, 200), "messages"); len(msgs) != 2 || msgs[0].(map[string]any)["body"] != "Book II hit hard" {
		t.Fatalf("messages = %v", msgs)
	}
	if n := len(list(h.do("GET", "/v1/circles?source=meditations-marcus-aurelius", "", nil, 200), "circles")); n != 1 {
		t.Fatalf("circles for book = %d", n)
	}
	if n := len(list(h.do("GET", "/v1/circles?mine=1", bob, nil, 200), "circles")); n != 1 {
		t.Fatalf("my circles = %d", n)
	}
	// The owner can remove anyone's message; members only their own.
	h.do("DELETE", "/v1/circles/"+id+"/messages/"+m["id"].(string), ada, nil, 204)
	// When the owner leaves, Bob takes over; when he leaves too, the circle goes.
	h.do("POST", "/v1/circles/"+id+"/leave", ada, nil, 204)
	if c := h.do("GET", "/v1/circles/"+id, bob, nil, 200); c["role"] != "owner" || c["owner"].(map[string]any)["display_name"] != "Bob" {
		t.Fatalf("after owner left = %v", c)
	}
	h.do("POST", "/v1/circles/"+id+"/leave", bob, nil, 204)
	h.do("GET", "/v1/circles/"+id, bob, nil, 404)
}

func TestPremiumAndDashboard(t *testing.T) {
	h := setup(t)
	ada, _ := h.registerAs("ada@example.com", "Ada")
	p := h.do("GET", "/v1/premium", "", nil, 200)
	if len(list(p, "plans")) != 2 || p["providers"].(map[string]any)["stripe"] != false {
		t.Fatalf("premium = %v", p)
	}
	h.do("POST", "/v1/premium/checkout", ada, map[string]any{"plan": "monthly"}, 503)

	var lastForm url.Values
	stripe := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		lastForm = r.PostForm
		switch r.URL.Path {
		case "/v1/checkout/sessions":
			fmt.Fprint(w, `{"id":"cs_sub","url":"https://checkout.stripe.test/sub"}`)
		case "/v1/billing_portal/sessions":
			fmt.Fprint(w, `{"url":"https://billing.stripe.test/p"}`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer stripe.Close()
	h.api.Stripe = &payments.Stripe{SecretKey: "sk", WebhookSecret: "whsec", BaseURL: stripe.URL, Now: func() time.Time { return h.now }}
	h.api.StripePrices = map[string]string{"monthly": "price_m"}
	me := h.do("GET", "/v1/me", ada, nil, 200)
	uid := me["id"].(string)

	if out := h.do("POST", "/v1/premium/checkout", ada, map[string]any{"plan": "monthly"}, 201); out["url"] != "https://checkout.stripe.test/sub" ||
		lastForm.Get("line_items[0][price]") != "price_m" || lastForm.Get("subscription_data[metadata][user_id]") != uid {
		t.Fatalf("checkout = %v, form = %v", out, lastForm)
	}
	h.do("POST", "/v1/premium/checkout", ada, map[string]any{"plan": "yearly"}, 503) // no price set
	h.do("POST", "/v1/premium/portal", ada, nil, 404)                                // no customer yet

	webhook := func(body string) {
		ts := h.now.Unix()
		mac := hmac.New(sha256.New, []byte("whsec"))
		fmt.Fprintf(mac, "%d.%s", ts, body)
		req, _ := http.NewRequest("POST", h.srv.URL+"/v1/webhooks/stripe", bytes.NewBufferString(body))
		req.Header.Set("Stripe-Signature", fmt.Sprintf("t=%d,v1=%s", ts, hex.EncodeToString(mac.Sum(nil))))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 204 {
			t.Fatalf("webhook = %d", resp.StatusCode)
		}
	}
	webhook(fmt.Sprintf(`{"type":"checkout.session.completed","data":{"object":{"id":"cs_sub","mode":"subscription","customer":"cus_1","metadata":{"user_id":%q}}}}`, uid))
	end := time.Now().Add(30 * 24 * time.Hour).Unix()
	webhook(fmt.Sprintf(`{"type":"customer.subscription.created","data":{"object":{"id":"sub_1","status":"active","metadata":{"user_id":%q,"plan":"monthly"},"items":{"data":[{"current_period_end":%d}]}}}}`, uid, end))
	p = h.do("GET", "/v1/premium", ada, nil, 200)
	if p["premium"] != true || p["subscription"].(map[string]any)["provider"] != "stripe" {
		t.Fatalf("premium after webhook = %v", p)
	}
	if out := h.do("POST", "/v1/premium/portal", ada, nil, 201); out["url"] != "https://billing.stripe.test/p" || lastForm.Get("customer") != "cus_1" {
		t.Fatalf("portal = %v", out)
	}
	// Later updates find the subscription without metadata; an unpaid one stops premium.
	webhook(fmt.Sprintf(`{"type":"customer.subscription.updated","data":{"object":{"id":"sub_1","status":"unpaid","metadata":{},"current_period_end":%d}}}`, end))
	if p := h.do("GET", "/v1/premium", ada, nil, 200); p["premium"] != false {
		t.Fatalf("premium after unpaid = %v", p)
	}

	// The dashboard is for moderators.
	h.do("GET", "/v1/admin/stats", ada, nil, 403)
	if err := h.st.SetRole(context.Background(), "ada@example.com", "moderator"); err != nil {
		t.Fatal(err)
	}
	h.do("POST", "/v1/seen", ada, map[string]any{"post_ids": []string{"nhs-sleep-tips--01"}}, 204)
	st := h.do("GET", "/v1/admin/stats", ada, nil, 200)
	users := st["users"].(map[string]any)
	if users["total"].(float64) != 1 || len(list(st, "daily")) != 30 || st["content"].(map[string]any)["posts"].(float64) != 9 {
		t.Fatalf("stats = %v", st)
	}
}
