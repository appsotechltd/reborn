package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/payments"
)

func posts(m map[string]any) []map[string]any {
	var out []map[string]any
	for _, p := range list(m, "posts") {
		out = append(out, p.(map[string]any))
	}
	return out
}

func postIDsOf(ps []map[string]any) []string {
	var out []string
	for _, p := range ps {
		out = append(out, p["id"].(string))
	}
	return out
}

func (h *harness) registerAs(email, name string) (token, handle string) {
	out := h.do("POST", "/v1/auth/register", "", map[string]any{"email": email, "password": "password1", "display_name": name}, 201)
	return out["token"].(string), out["user"].(map[string]any)["handle"].(string)
}

func TestTimeline(t *testing.T) {
	h := setup(t)
	tok, _ := h.registerAs("ada@example.com", "Ada Lovelace")

	// A card added later is a newer post.
	if _, err := h.st.DB.Exec(context.Background(), `UPDATE cards SET published_at = now() + interval '1 day' WHERE id = 'nhs-sleep-tips--02'`); err != nil {
		t.Fatal(err)
	}
	first := posts(h.do("GET", "/v1/timeline?limit=4", tok, nil, 200))
	if len(first) != 4 || first[0]["id"] != "nhs-sleep-tips--02" {
		t.Fatalf("newest post not first: %v", postIDsOf(first))
	}
	if r := first[0]["reason"].(map[string]any); r["kind"] != "new" {
		t.Fatalf("reason with no topics or follows = %v", r)
	}
	if v := first[0]["viewer"].(map[string]any); v["seen"] != false || v["favorited"] != false || v["reaction"] != nil {
		t.Fatalf("viewer = %v", v)
	}

	// Marking the first page seen while scrolling doesn't shift the next page.
	page1 := h.do("GET", "/v1/timeline?limit=5", tok, nil, 200)
	h.do("POST", "/v1/seen", tok, map[string]any{"post_ids": postIDsOf(posts(page1))}, 204)
	page2 := h.do("GET", "/v1/timeline?limit=5&cursor="+page1["next_cursor"].(string), tok, nil, 200)
	all := append(postIDsOf(posts(page1)), postIDsOf(posts(page2))...)
	uniq := map[string]bool{}
	for _, id := range all {
		uniq[id] = true
	}
	if len(all) != 9 || len(uniq) != 9 {
		t.Fatalf("pages overlap or skip: %v", all)
	}

	// Next time the app opens, unseen posts come first and seen ones last.
	h.now = h.now.Add(time.Minute)
	reopened := posts(h.do("GET", "/v1/timeline?limit=9", tok, nil, 200))
	for i, p := range reopened {
		seen := p["viewer"].(map[string]any)["seen"].(bool)
		if seen != (i >= 4) {
			t.Fatalf("unseen-first order broken at %d: %v", i, postIDsOf(reopened))
		}
	}

	// Topics narrow the timeline; follows widen it again.
	h.do("PATCH", "/v1/me", tok, map[string]any{"topics": []string{"health"}}, 200)
	for _, p := range posts(h.do("GET", "/v1/timeline", tok, nil, 200)) {
		if !strings.HasPrefix(p["id"].(string), "nhs-") || p["reason"].(map[string]any)["label"] != "Health & Wellness" {
			t.Fatalf("topic timeline leaked %v", p["id"])
		}
	}
	st := h.do("PUT", "/v1/follows/source/meditations-marcus-aurelius", tok, nil, 200)
	if st["followers"].(float64) != 1 || st["is_following"] != true {
		t.Fatalf("follow state = %v", st)
	}
	h.do("PUT", "/v1/follows/source/nope", tok, nil, 404)
	reasons := map[string]string{}
	for _, p := range posts(h.do("GET", "/v1/timeline", tok, nil, 200)) {
		reasons[p["id"].(string)] = p["reason"].(map[string]any)["kind"].(string)
	}
	if len(reasons) != 6 || reasons["meditations-marcus-aurelius--01"] != "source" {
		t.Fatalf("follow didn't add the book: %v", reasons)
	}
	h.do("DELETE", "/v1/follows/source/meditations-marcus-aurelius", tok, nil, 200)
	h.do("PUT", "/v1/follows/author/"+url.PathEscape("Marcus Aurelius"), tok, nil, 200)
	for _, p := range posts(h.do("GET", "/v1/timeline", tok, nil, 200)) {
		if r := p["reason"].(map[string]any); strings.HasPrefix(p["id"].(string), "meditations") && (r["kind"] != "author" || r["label"] != "Marcus Aurelius") {
			t.Fatalf("author reason = %v", r)
		}
	}
	a := h.do("GET", "/v1/authors/"+url.PathEscape("Marcus Aurelius"), tok, nil, 200)
	if a["is_following"] != true || len(list(a, "sources")) != 1 || len(list(a, "cards")) != int(a["card_count"].(float64)) || len(list(a, "cards")) == 0 {
		t.Fatalf("author page = %v", a)
	}
	src := h.do("GET", "/v1/sources/nhs-sleep-tips", tok, nil, 200)
	if src["follow"].(map[string]any)["is_following"] != false {
		t.Fatalf("source follow = %v", src["follow"])
	}

	// Following a person brings in what they favourite.
	bobTok, bobHandle := h.registerAs("bob@example.com", "Bob Smith")
	if bobHandle != "bob_smith" {
		t.Fatalf("handle = %q", bobHandle)
	}
	h.do("PUT", "/v1/posts/fixture-psychology-notes--01/favorite", bobTok, nil, 204)
	bob := h.do("GET", "/v1/users/"+bobHandle, tok, nil, 200)
	h.do("PUT", "/v1/follows/user/"+bob["id"].(string), tok, nil, 200)
	var fav map[string]any
	for _, p := range posts(h.do("GET", "/v1/timeline?limit=50", tok, nil, 200)) {
		if p["id"] == "fixture-psychology-notes--01" {
			fav = p["reason"].(map[string]any)
		}
	}
	if fav == nil || fav["kind"] != "favorite" || fav["label"] != "Bob Smith" {
		t.Fatalf("friend's favourite reason = %v", fav)
	}
	bob = h.do("GET", "/v1/users/"+bobHandle, tok, nil, 200)
	if bob["followers"].(float64) != 1 || bob["is_following"] != true || bob["favorites"].(float64) != 1 || bob["email"] != nil {
		t.Fatalf("profile = %v", bob)
	}
	me := h.do("GET", "/v1/me", tok, nil, 200)
	h.do("PUT", "/v1/follows/user/"+me["id"].(string), tok, nil, 400)
	following := list(h.do("GET", "/v1/me/following", tok, nil, 200), "following")
	if len(following) != 2 {
		t.Fatalf("following = %v", following)
	}
	if n := len(list(h.do("GET", "/v1/users/"+bobHandle+"/followers", "", nil, 200), "users")); n != 1 {
		t.Fatalf("followers = %d", n)
	}
	if n := len(posts(h.do("GET", "/v1/users/"+bobHandle+"/favorites", "", nil, 200))); n != 1 {
		t.Fatalf("profile favourites = %d", n)
	}

	// Anonymous timelines work too.
	if n := len(posts(h.do("GET", "/v1/timeline?topics=health", "", nil, 200))); n != 3 {
		t.Fatalf("anonymous topic timeline = %d", n)
	}
	h.do("GET", "/v1/timeline?cursor=bogus", "", nil, 400)
	h.do("POST", "/v1/seen", "", map[string]any{"post_ids": []string{"x"}}, 401)
}

func TestPostInteractions(t *testing.T) {
	h := setup(t)
	ada, _ := h.registerAs("ada@example.com", "Ada")
	bob, _ := h.registerAs("bob@example.com", "Bob")
	const id = "nhs-sleep-tips--01"
	path := "/v1/posts/" + id

	h.do("PUT", path+"/favorite", ada, nil, 204)
	h.do("PUT", path+"/favorite", ada, nil, 204) // idempotent
	h.do("PUT", path+"/reaction", ada, map[string]any{"kind": "love"}, 204)
	h.do("PUT", path+"/reaction", bob, map[string]any{"kind": "love"}, 204)
	h.do("PUT", path+"/reaction", bob, map[string]any{"kind": "insightful"}, 204) // replaces
	h.do("PUT", path+"/reaction", bob, map[string]any{"kind": "angry"}, 400)
	h.do("POST", path+"/share", "", map[string]any{"channel": "whatsapp"}, 204)
	h.do("POST", path+"/share", ada, map[string]any{"channel": "myspace"}, 400)
	h.do("PUT", "/v1/posts/nope--01/favorite", ada, nil, 404)

	p := h.do("GET", path, ada, nil, 200)
	stats := p["stats"].(map[string]any)
	rx := stats["reactions"].(map[string]any)
	if rx["love"].(float64) != 1 || rx["insightful"].(float64) != 1 || stats["favorites"].(float64) != 1 || stats["shares"].(float64) != 1 {
		t.Fatalf("stats = %v", stats)
	}
	if v := p["viewer"].(map[string]any); v["reaction"] != "love" || v["favorited"] != true {
		t.Fatalf("viewer = %v", v)
	}
	if p["card"].(map[string]any)["disclaimer"] == nil {
		t.Fatal("post lost the health disclaimer")
	}
	if favs := posts(h.do("GET", "/v1/me/favorites", ada, nil, 200)); len(favs) != 1 || favs[0]["id"] != id {
		t.Fatalf("favourites = %v", favs)
	}
	h.do("DELETE", path+"/favorite", ada, nil, 204)
	h.do("DELETE", path+"/reaction", ada, nil, 204)
	if v := h.do("GET", path, ada, nil, 200)["viewer"].(map[string]any); v["reaction"] != nil || v["favorited"] != false {
		t.Fatalf("viewer after undo = %v", v)
	}

	// Comments, one level of replies, reports and moderation.
	c1 := h.do("POST", path+"/comments", ada, map[string]any{"body": "  Trying this tonight. "}, 201)
	if c1["body"] != "Trying this tonight." || c1["author"].(map[string]any)["display_name"] != "Ada" {
		t.Fatalf("comment = %v", c1)
	}
	r1 := h.do("POST", path+"/comments", bob, map[string]any{"body": "Let us know!", "parent_id": c1["id"]}, 201)
	r2 := h.do("POST", path+"/comments", ada, map[string]any{"body": "Will do", "parent_id": r1["id"]}, 201)
	if r2["parent_id"] != c1["id"] {
		t.Fatalf("reply to a reply should attach to the top comment: %v", r2)
	}
	h.do("POST", path+"/comments", ada, map[string]any{"body": ""}, 400)
	h.do("POST", path+"/comments", ada, map[string]any{"body": "x", "parent_id": "00000000-0000-0000-0000-000000000000"}, 404)
	if n := len(list(h.do("GET", path+"/comments", "", nil, 200), "comments")); n != 3 {
		t.Fatalf("comments = %d", n)
	}
	h.do("DELETE", "/v1/comments/"+r2["id"].(string), bob, nil, 404) // not Bob's
	h.do("DELETE", "/v1/comments/"+r2["id"].(string), ada, nil, 204)

	carol, _ := h.registerAs("carol@example.com", "Carol")
	dan, _ := h.registerAs("dan@example.com", "Dan")
	for _, tok := range []string{ada, carol, dan} {
		h.do("POST", "/v1/comments/"+r1["id"].(string)+"/report", tok, map[string]any{"reason": "spam"}, 204)
	}
	if n := len(list(h.do("GET", path+"/comments", "", nil, 200), "comments")); n != 1 {
		t.Fatalf("reported comment still visible: %d comments", n)
	}
	if n := h.do("GET", path, "", nil, 200)["stats"].(map[string]any)["comments"].(float64); n != 1 {
		t.Fatalf("comment count = %v", n)
	}
	h.do("GET", "/v1/moderation/comments", ada, nil, 403)
	if err := h.st.SetRole(context.Background(), "carol@example.com", "moderator"); err != nil {
		t.Fatal(err)
	}
	queue := list(h.do("GET", "/v1/moderation/comments", carol, nil, 200), "comments")
	if len(queue) != 1 || queue[0].(map[string]any)["reports"].(float64) != 3 {
		t.Fatalf("queue = %v", queue)
	}
	h.do("POST", "/v1/moderation/comments/"+r1["id"].(string)+"/restore", carol, nil, 204)
	if n := len(list(h.do("GET", path+"/comments", "", nil, 200), "comments")); n != 2 {
		t.Fatalf("restored comment missing: %d", n)
	}
	if n := len(list(h.do("GET", "/v1/moderation/comments", carol, nil, 200), "comments")); n != 0 {
		t.Fatalf("queue not cleared: %d", n)
	}

	// Profile edits.
	h.do("PATCH", "/v1/me", ada, map[string]any{"handle": "@Ada_L", "bio": "Reads at night."}, 200)
	if me := h.do("GET", "/v1/me", ada, nil, 200); me["handle"] != "ada_l" || me["bio"] != "Reads at night." {
		t.Fatalf("me = %v", me)
	}
	h.do("PATCH", "/v1/me", bob, map[string]any{"handle": "ada_l"}, 409)
	h.do("PATCH", "/v1/me", bob, map[string]any{"handle": "no"}, 400)

	// Deleting an account removes its comments and reactions.
	h.do("DELETE", "/v1/me", bob, nil, 204)
	h.do("GET", "/v1/me", bob, nil, 404)
	if n := len(list(h.do("GET", path+"/comments", "", nil, 200), "comments")); n != 1 {
		t.Fatalf("deleted user's comment remains: %d", n)
	}
}

type fakeMailer struct {
	mu   sync.Mutex
	sent []string
}

func (m *fakeMailer) Send(_ context.Context, to, subject, body string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sent = append(m.sent, to+"\n"+body)
	return nil
}

func TestPasswordReset(t *testing.T) {
	h := setup(t)
	m := &fakeMailer{}
	h.api.Mailer, h.api.WebBaseURL = m, "https://reborn.test"
	h.registerAs("ada@example.com", "Ada")

	h.do("POST", "/v1/auth/forgot", "", map[string]any{"email": "nobody@example.com"}, 202)
	h.do("POST", "/v1/auth/forgot", "", map[string]any{"email": "ADA@example.com"}, 202)
	if len(m.sent) != 1 || !strings.HasPrefix(m.sent[0], "ada@example.com\n") {
		t.Fatalf("emails = %v", m.sent)
	}
	_, after, ok := strings.Cut(m.sent[0], "https://reborn.test/reset-password?token=")
	if !ok {
		t.Fatalf("no link in %q", m.sent[0])
	}
	token := strings.Fields(after)[0]

	h.do("POST", "/v1/auth/reset", "", map[string]any{"token": token, "password": "short"}, 400)
	h.do("POST", "/v1/auth/reset", "", map[string]any{"token": "wrong", "password": "new-password"}, 400)
	out := h.do("POST", "/v1/auth/reset", "", map[string]any{"token": token, "password": "new-password"}, 200)
	if out["token"] == nil {
		t.Fatal("reset should sign the user in")
	}
	h.do("POST", "/v1/auth/reset", "", map[string]any{"token": token, "password": "another-one"}, 400) // used
	h.do("POST", "/v1/auth/login", "", map[string]any{"email": "ada@example.com", "password": "password1"}, 401)
	h.do("POST", "/v1/auth/login", "", map[string]any{"email": "ada@example.com", "password": "new-password"}, 200)

	// Links expire.
	h.do("POST", "/v1/auth/forgot", "", map[string]any{"email": "ada@example.com"}, 202)
	_, after, _ = strings.Cut(m.sent[len(m.sent)-1], "token=")
	h.now = h.now.Add(2 * time.Hour)
	h.do("POST", "/v1/auth/reset", "", map[string]any{"token": strings.Fields(after)[0], "password": "new-password-2"}, 400)
}

func TestStripeGift(t *testing.T) {
	h := setup(t)
	tok, _ := h.registerAs("ada@example.com", "Ada")
	if p := h.do("GET", "/v1/gifts/tiers", "", nil, 200)["providers"].(map[string]any); p["stripe"] != false {
		t.Fatalf("providers = %v", p)
	}
	h.do("POST", "/v1/posts/nhs-sleep-tips--01/gifts/checkout", tok, map[string]any{"tier": "spark"}, 503)

	var form url.Values
	stripe := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		form, _ = url.ParseQuery(string(b))
		if user, _, _ := r.BasicAuth(); user != "sk_test" || r.URL.Path != "/v1/checkout/sessions" {
			http.Error(w, "bad", 401)
			return
		}
		fmt.Fprint(w, `{"id":"cs_test_1","url":"https://checkout.stripe.test/cs_test_1"}`)
	}))
	defer stripe.Close()
	h.api.Stripe = &payments.Stripe{SecretKey: "sk_test", WebhookSecret: "whsec_test", BaseURL: stripe.URL, Now: func() time.Time { return h.now }}
	h.api.WebBaseURL = "https://reborn.test"

	h.do("POST", "/v1/posts/nhs-sleep-tips--01/gifts/checkout", tok, map[string]any{"tier": "huge"}, 400)
	out := h.do("POST", "/v1/posts/nhs-sleep-tips--01/gifts/checkout", tok, map[string]any{"tier": "lamp"}, 201)
	giftID := out["gift_id"].(string)
	if out["url"] != "https://checkout.stripe.test/cs_test_1" || form.Get("line_items[0][price_data][unit_amount]") != "499" ||
		form.Get("metadata[gift_id]") != giftID || form.Get("success_url") != "https://reborn.test/ideas/nhs-sleep-tips--01?gift="+giftID {
		t.Fatalf("checkout = %v, form = %v", out, form)
	}
	if g := h.do("GET", "/v1/gifts/"+giftID, tok, nil, 200); g["status"] != "pending" {
		t.Fatalf("gift = %v", g)
	}

	event := fmt.Sprintf(`{"type":"checkout.session.completed","data":{"object":{"id":"cs_test_1","payment_status":"paid","metadata":{"gift_id":%q}}}}`, giftID)
	send := func(sig string, want int) {
		req, _ := http.NewRequest("POST", h.srv.URL+"/v1/webhooks/stripe", bytes.NewBufferString(event))
		req.Header.Set("Stripe-Signature", sig)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != want {
			t.Fatalf("webhook = %d, want %d", resp.StatusCode, want)
		}
	}
	ts := h.now.Unix()
	mac := hmac.New(sha256.New, []byte("whsec_test"))
	fmt.Fprintf(mac, "%d.%s", ts, event)
	good := hex.EncodeToString(mac.Sum(nil))
	// Change the first hex digit; a fixed "00" prefix was no change when the real MAC began with it.
	bad := "0" + good[1:]
	if good[0] == '0' {
		bad = "1" + good[1:]
	}
	send(fmt.Sprintf("t=%d,v1=%s", ts, bad), 400)
	send(fmt.Sprintf("t=%d,v1=%s", ts, hex.EncodeToString(mac.Sum(nil))), 204)
	send(fmt.Sprintf("t=%d,v1=%s", ts, hex.EncodeToString(mac.Sum(nil))), 204) // retries are harmless

	if g := h.do("GET", "/v1/gifts/"+giftID, tok, nil, 200); g["status"] != "paid" {
		t.Fatalf("gift = %v", g)
	}
	if n := h.do("GET", "/v1/posts/nhs-sleep-tips--01", "", nil, 200)["stats"].(map[string]any)["gifts"].(float64); n != 1 {
		t.Fatalf("gift count = %v", n)
	}
}
