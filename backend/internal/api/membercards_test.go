package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/rebornai"
)

func TestMemberCards(t *testing.T) {
	h := setup(t)
	ada, adaHandle := h.registerAs("ada@example.com", "Ada")
	bob, _ := h.registerAs("bob@example.com", "Bob")
	cat, _ := h.registerAs("cat@example.com", "Cat")

	// Categories are Ada's own; names are unique per member.
	walks := h.do("POST", "/v1/me/categories", ada, map[string]any{"name": "  Morning   walks "}, 201)
	if walks["name"] != "Morning walks" {
		t.Fatalf("category = %v", walks)
	}
	h.do("POST", "/v1/me/categories", ada, map[string]any{"name": "morning walks"}, 409)
	h.do("POST", "/v1/me/categories", ada, map[string]any{"name": ""}, 400)
	walksID := walks["id"].(string)

	// Writing cards.
	h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "No body", "topic": "psychology"}, 400)
	h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Bad topic", "body": "x", "topic": "nope"}, 400)
	h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Wrong category", "body": "x", "topic": "psychology", "category_id": "00000000-0000-0000-0000-000000000000"}, 404)
	h.do("POST", "/v1/me/cards", bob, map[string]any{"title": "Not my category", "body": "x", "topic": "psychology", "category_id": walksID}, 404)
	pub := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Walk before your phone", "body": "Ten minutes outside before any screen sets the tone for the day.",
		"apply_it": "Leave your phone by the door tomorrow.", "topic": "psychology", "category_id": walksID}, 201)
	pubID := pub["id"].(string)
	if !strings.HasPrefix(pubID, "walk-before-your-phone-") || !strings.HasSuffix(pubID, "--01") || pub["visibility"] != "everyone" ||
		pub["author"].(map[string]any)["handle"] != adaHandle || pub["category"].(map[string]any)["name"] != "Morning walks" ||
		pub["credit"] != "Written by Ada on Reborn" {
		t.Fatalf("card = %v", pub)
	}
	fans := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "For my followers", "body": "Only followers see this.", "topic": "psychology", "audience": "followers"}, 201)
	secret := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "My secret", "body": "Only me.", "topic": "psychology", "audience": "private"}, 201)
	if fans["visibility"] != "followers" || secret["visibility"] != "private" {
		t.Fatalf("visibility = %v / %v", fans["visibility"], secret["visibility"])
	}

	// Ada sees all three; the categories count them.
	if mine := list(h.do("GET", "/v1/me/cards", ada, nil, 200), "cards"); len(mine) != 3 {
		t.Fatalf("my cards = %d", len(mine))
	}
	if inWalks := list(h.do("GET", "/v1/me/cards?category="+walksID, ada, nil, 200), "cards"); len(inWalks) != 1 {
		t.Fatalf("walks = %d", len(inWalks))
	}
	if cats := list(h.do("GET", "/v1/me/categories", ada, nil, 200), "categories"); cats[0].(map[string]any)["card_count"] != 1.0 {
		t.Fatalf("categories = %v", cats)
	}

	// Others: Bob doesn't follow Ada, so he sees only the public card.
	page := h.do("GET", "/v1/users/"+adaHandle+"/cards", bob, nil, 200)
	if posts := list(page, "posts"); len(posts) != 1 || len(list(page, "categories")) != 1 {
		t.Fatalf("Ada's page for Bob = %v", page)
	}
	if p := h.do("GET", "/v1/users/"+adaHandle, bob, nil, 200); p["cards"] != 1.0 {
		t.Fatalf("profile = %v", p)
	}
	h.do("GET", "/v1/posts/"+fans["id"].(string), bob, nil, 404)
	h.do("GET", "/v1/posts/"+secret["id"].(string), bob, nil, 404)
	h.do("GET", "/v1/posts/"+pubID, "", nil, 200)
	// Member cards stay out of the library: search, books and the sitemap.
	for _, c := range list(h.do("GET", "/v1/search?q=walk+phone", "", nil, 200), "cards") {
		if c.(map[string]any)["id"] == pubID {
			t.Fatal("search found a member card")
		}
	}
	sm := h.do("GET", "/v1/sitemap", "", nil, 200)
	for _, c := range list(sm, "cards") {
		if strings.Contains(c.(map[string]any)["id"].(string), "walk-before") {
			t.Fatal("member card in sitemap")
		}
	}
	for _, s := range list(h.do("GET", "/v1/sources?limit=100", "", nil, 200), "sources") {
		if s.(map[string]any)["id"] == "reborn-members" {
			t.Fatal("members source listed as a book")
		}
	}

	// Following Ada shows her followers-only card, and puts her cards first.
	h.do("PUT", "/v1/follows/user/"+pub["author"].(map[string]any)["id"].(string), bob, nil, 200)
	h.do("GET", "/v1/posts/"+fans["id"].(string), bob, nil, 200)
	tl := list(h.do("GET", "/v1/timeline?limit=3", bob, nil, 200), "posts")
	for _, p := range tl[:2] {
		pm := p.(map[string]any)
		if pm["reason"].(map[string]any)["kind"] != "writer" || pm["reason"].(map[string]any)["label"] != "Ada" {
			t.Fatalf("timeline = %v", tl)
		}
	}

	// Collections take member cards; Ada can keep her private card in hers.
	st := h.do("POST", "/v1/stashes", ada, map[string]any{"name": "Keep"}, 201)
	h.do("PUT", "/v1/stashes/"+st["id"].(string)+"/cards/"+secret["id"].(string), ada, nil, 204)
	if cards := list(h.do("GET", "/v1/stashes/"+st["id"].(string), ada, nil, 200), "cards"); len(cards) != 1 {
		t.Fatalf("collection = %v", cards)
	}
	bst := h.do("POST", "/v1/stashes", bob, map[string]any{"name": "Keep"}, 201)
	h.do("PUT", "/v1/stashes/"+bst["id"].(string)+"/cards/"+secret["id"].(string), bob, nil, 404)
	h.do("PUT", "/v1/stashes/"+bst["id"].(string)+"/cards/"+pubID, bob, nil, 204)

	// Editing: only Ada can, and making it private takes it off her page.
	h.do("PATCH", "/v1/me/cards/"+pubID, bob, map[string]any{"title": "Mine now"}, 404)
	ed := h.do("PATCH", "/v1/me/cards/"+pubID, ada, map[string]any{"title": "Walk first", "category_id": ""}, 200)
	if ed["title"] != "Walk first" || ed["category"] != nil || ed["id"] != pubID {
		t.Fatalf("edit = %v", ed)
	}

	// Reports: three hide the card until a moderator looks.
	h.do("POST", "/v1/posts/nhs-sleep-tips--01/report", bob, nil, 404) // library cards aren't reported
	h.do("POST", "/v1/posts/"+pubID+"/report", bob, map[string]any{"reason": "spam"}, 204)
	h.do("POST", "/v1/posts/"+pubID+"/report", cat, nil, 204)
	dan, _ := h.registerAs("dan@example.com", "Dan")
	h.do("POST", "/v1/posts/"+pubID+"/report", dan, nil, 204)
	h.do("GET", "/v1/posts/"+pubID, "", nil, 404)
	if c := h.do("GET", "/v1/me/cards/"+pubID, ada, nil, 200); c["visibility"] != "hidden" {
		t.Fatalf("reported card = %v", c)
	}
	// A hidden card stays hidden when Ada changes its audience.
	h.do("PATCH", "/v1/me/cards/"+pubID, ada, map[string]any{"audience": "everyone"}, 200)
	h.do("GET", "/v1/posts/"+pubID, "", nil, 404)
	h.do("GET", "/v1/moderation/cards", bob, nil, 403)
	if err := h.st.SetRole(t.Context(), "cat@example.com", "moderator"); err != nil {
		t.Fatal(err)
	}
	q := list(h.do("GET", "/v1/moderation/cards", cat, nil, 200), "cards")
	if len(q) != 1 || q[0].(map[string]any)["reports"] != 3.0 || q[0].(map[string]any)["status"] != "hidden" {
		t.Fatalf("queue = %v", q)
	}
	h.do("POST", "/v1/moderation/cards/"+pubID+"/restore", cat, nil, 204)
	h.do("GET", "/v1/posts/"+pubID, "", nil, 200)

	// Deleting.
	h.do("DELETE", "/v1/me/cards/"+secret["id"].(string), bob, nil, 404)
	h.do("DELETE", "/v1/me/cards/"+secret["id"].(string), ada, nil, 204)
	h.do("GET", "/v1/me/cards/"+secret["id"].(string), ada, nil, 404)
	h.do("DELETE", "/v1/me/categories/"+walksID, ada, nil, 204)
}

func TestCardStudio(t *testing.T) {
	h := setup(t)
	ada, _ := h.registerAs("ada@example.com", "Ada")
	card := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Sleep on it", "body": "Big decisions look different after a night's sleep. Wait a day.",
		"topic": "psychology"}, 201)
	id := card["id"].(string)
	studio := h.do("GET", "/v1/studio", "", nil, 200)
	if studio["available"] != false || len(list(studio, "voices")) != 12 || len(list(studio, "rates")) != 5 {
		t.Fatalf("studio = %v", studio)
	}
	h.do("POST", "/v1/me/cards/"+id+"/image", ada, map[string]any{"style": "illustration"}, 503)
	f := h.withAI(40)
	h.do("POST", "/v1/me/cards/"+id+"/image", ada, map[string]any{"style": "illustration"}, 403) // premium only
	h.makePremium(ada)
	h.do("POST", "/v1/me/cards/"+id+"/image", ada, map[string]any{"style": "huge"}, 400)
	bob, _ := h.registerAs("bob@example.com", "Bob")
	h.makePremium(bob)
	h.do("POST", "/v1/me/cards/"+id+"/image", bob, map[string]any{"style": "sketch"}, 404) // not Bob's card

	// An illustration is 4 units.
	out := h.do("POST", "/v1/me/cards/"+id+"/image", ada, map[string]any{"style": "illustration", "prompt": "A calm bedroom at dawn"}, 200)
	img := out["card"].(map[string]any)["image"].(map[string]any)
	if out["units"] != 4.0 || wallet(out)["remaining"] != 36.0 || !strings.HasPrefix(img["url"].(string), "/media/ai/images/") ||
		f.prompts[0] != "gpt-image-1-mini medium 1536x1024" {
		t.Fatalf("image = %v, prompts %v", out, f.prompts)
	}

	// Audio: 1 unit per 50 words, in the chosen voice.
	var voices []string
	kokoro := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var in struct{ Voice string }
		_ = json.NewDecoder(r.Body).Decode(&in)
		voices = append(voices, in.Voice)
		w.Header().Set("Content-Type", "audio/mpeg")
		fmt.Fprint(w, "kokoro-mp3")
	}))
	defer kokoro.Close()
	h.api.AI.Kokoro = &rebornai.OpenAI{BaseURL: kokoro.URL}
	h.do("POST", "/v1/me/cards/"+id+"/audio", ada, map[string]any{"voice": "zz_nobody"}, 400)
	out = h.do("POST", "/v1/me/cards/"+id+"/audio", ada, map[string]any{"voice": "bm_george"}, 200)
	audio := out["card"].(map[string]any)["audio"].(map[string]any)
	if out["units"] != 1.0 || wallet(out)["remaining"] != 35.0 || audio["voice_name"] != "George" || len(voices) != 1 || voices[0] != "bm_george" {
		t.Fatalf("audio = %v, voices %v", out, voices)
	}

	// Video: 1 to plan + 4 illustrations + narration = 18 units here; the narration is reused.
	out = h.do("POST", "/v1/me/cards/"+id+"/video", ada, nil, 200)
	video := out["card"].(map[string]any)["video"].(map[string]any)
	if out["units"] != 18.0 || wallet(out)["remaining"] != 17.0 || len(list(video, "scenes")) != 4 || video["voice"] != "af_heart" ||
		f.images != 5 || len(voices) != 2 {
		t.Fatalf("video = %v (images %d, voices %v)", out, f.images, voices)
	}
	// Not enough units for another video.
	if out = h.do("POST", "/v1/me/cards/"+id+"/video", ada, map[string]any{"voice": "af_bella"}, 402); wallet(out)["remaining"] != 17.0 {
		t.Fatalf("402 = %v", out)
	}
	// Removing media is free.
	c := h.do("DELETE", "/v1/me/cards/"+id+"/image", ada, nil, 200)
	if c["image"] != nil || c["video"] == nil {
		t.Fatalf("after delete = %v", c)
	}
	// Others see the video on the post.
	if p := h.do("GET", "/v1/posts/"+id, bob, nil, 200); p["card"].(map[string]any)["video"] == nil {
		t.Fatalf("post = %v", p)
	}
	if u := list(h.do("GET", "/v1/ai/usage", ada, nil, 200), "usage"); len(u) != 3 || u[0].(map[string]any)["kind"] != "video" {
		t.Fatalf("usage = %v", u)
	}
}

func TestCreatorGifts(t *testing.T) {
	h := setup(t)
	ada, _ := h.registerAs("ada@example.com", "Ada")
	bob, _ := h.registerAs("bob@example.com", "Bob")
	card := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Give first", "body": "Help before you ask.", "topic": "psychology"}, 201)
	id := card["id"].(string)
	h.api.GiftCommission, h.api.StoreFee = 30, 15
	if tiers := h.do("GET", "/v1/gifts/tiers", "", nil, 200); tiers["commission_percent"] != 30.0 {
		t.Fatalf("tiers = %v", tiers)
	}

	stripe := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"id":"cs_gift_1","url":"https://checkout.stripe.test/cs_gift_1"}`)
	}))
	defer stripe.Close()
	h.api.Stripe = &payments.Stripe{SecretKey: "sk_test", WebhookSecret: "whsec_test", BaseURL: stripe.URL, Now: func() time.Time { return h.now }}
	h.do("POST", "/v1/posts/"+id+"/gifts/checkout", ada, map[string]any{"tier": "lamp"}, 400) // not to yourself
	out := h.do("POST", "/v1/posts/"+id+"/gifts/checkout", bob, map[string]any{"tier": "lamp"}, 201)
	giftID := out["gift_id"].(string)
	event := fmt.Sprintf(`{"type":"checkout.session.completed","data":{"object":{"id":"cs_gift_1","payment_status":"paid","metadata":{"gift_id":%q}}}}`, giftID)
	ts := h.now.Unix()
	mac := hmac.New(sha256.New, []byte("whsec_test"))
	fmt.Fprintf(mac, "%d.%s", ts, event)
	req, _ := http.NewRequest("POST", h.srv.URL+"/v1/webhooks/stripe", strings.NewReader(event))
	req.Header.Set("Stripe-Signature", fmt.Sprintf("t=%d,v1=%s", ts, hex.EncodeToString(mac.Sum(nil))))
	resp, err := http.DefaultClient.Do(req)
	if err != nil || resp.StatusCode != 204 {
		t.Fatalf("webhook = %v %v", resp, err)
	}
	// $4.99 on Stripe: fee 45c, Reborn 30% of the rest, Ada $3.17.
	e := h.do("GET", "/v1/me/earnings", ada, nil, 200)["earnings"].(map[string]any)
	if e["total_cents"] != 317.0 || e["gifts"] != 1.0 || len(list(e, "recent")) != 1 ||
		list(e, "recent")[0].(map[string]any)["from"].(map[string]any)["display_name"] != "Bob" {
		t.Fatalf("earnings = %v", e)
	}
	// Ada is told (in the background).
	deadline := time.Now().Add(5 * time.Second)
	for {
		n := list(h.do("GET", "/v1/notifications", ada, nil, 200), "notifications")
		if len(n) > 0 && n[0].(map[string]any)["kind"] == "gift" && strings.Contains(n[0].(map[string]any)["text"].(string), "$3.17") {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("notifications = %v", n)
		}
		time.Sleep(50 * time.Millisecond)
	}
	// Library gifts are Reborn's alone.
	if e := h.do("GET", "/v1/me/earnings", bob, nil, 200)["earnings"].(map[string]any); e["total_cents"] != 0.0 {
		t.Fatalf("bob earnings = %v", e)
	}
}

func TestWriterSubscriptions(t *testing.T) {
	h := setup(t)
	h.now = time.Now().UTC().Truncate(time.Second) // access is checked against the database clock
	h.api.GiftCommission, h.api.StoreFee = 30, 15
	ada, adaHandle := h.registerAs("ada@example.com", "Ada")
	bob, _ := h.registerAs("bob@example.com", "Bob")
	card := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Inner circle", "body": "For subscribers.", "topic": "psychology", "audience": "subscribers"}, 201)
	fans := h.do("POST", "/v1/me/cards", ada, map[string]any{"title": "Followers", "body": "For followers.", "topic": "psychology", "audience": "followers"}, 201)
	if card["visibility"] != "subscribers" {
		t.Fatalf("card = %v", card)
	}
	id := card["id"].(string)
	h.do("GET", "/v1/posts/"+id, bob, nil, 404)

	// No plan yet.
	plan := h.do("GET", "/v1/users/"+adaHandle+"/plan", bob, nil, 200)
	if plan["plan"] != nil || plan["locked_cards"] != 1.0 {
		t.Fatalf("plan = %v", plan)
	}
	h.do("POST", "/v1/users/"+adaHandle+"/subscribe/checkout", bob, nil, 503)
	var paths []string
	stripe := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		paths = append(paths, r.URL.Path)
		fmt.Fprint(w, `{"id":"cs_sub_1","url":"https://checkout.stripe.test/cs_sub_1"}`)
	}))
	defer stripe.Close()
	h.api.Stripe = &payments.Stripe{SecretKey: "sk_test", WebhookSecret: "whsec_test", BaseURL: stripe.URL, Now: func() time.Time { return h.now }}
	h.do("POST", "/v1/users/"+adaHandle+"/subscribe/checkout", bob, nil, 404) // no plan

	h.do("PUT", "/v1/me/plan", ada, map[string]any{"tier": "month_2", "enabled": true}, 400)
	if p := h.do("PUT", "/v1/me/plan", ada, map[string]any{"tier": "month_499", "enabled": true, "pitch": "Weekly deep dives"}, 200); p["tier"] != "month_499" {
		t.Fatalf("set plan = %v", p)
	}
	plan = h.do("GET", "/v1/users/"+adaHandle+"/plan", bob, nil, 200)
	if plan["tier"].(map[string]any)["amount_cents"] != 499.0 || plan["plan"].(map[string]any)["pitch"] != "Weekly deep dives" {
		t.Fatalf("plan = %v", plan)
	}
	h.do("POST", "/v1/users/"+adaHandle+"/subscribe/checkout", ada, nil, 400) // not yourself
	if out := h.do("POST", "/v1/users/"+adaHandle+"/subscribe/checkout", bob, nil, 201); out["url"] != "https://checkout.stripe.test/cs_sub_1" {
		t.Fatalf("checkout = %v", out)
	}

	adaID := card["author"].(map[string]any)["id"].(string)
	bobID := h.do("GET", "/v1/me", bob, nil, 200)["id"].(string)
	send := func(typ, status string, end time.Time) {
		event := fmt.Sprintf(`{"type":%q,"data":{"object":{"id":"sub_1","status":%q,"current_period_end":%d,
			"metadata":{"kind":"writer","subscriber_id":%q,"writer_id":%q,"tier":"month_499"}}}}`, typ, status, end.Unix(), bobID, adaID)
		ts := h.now.Unix()
		mac := hmac.New(sha256.New, []byte("whsec_test"))
		fmt.Fprintf(mac, "%d.%s", ts, event)
		req, _ := http.NewRequest("POST", h.srv.URL+"/v1/webhooks/stripe", strings.NewReader(event))
		req.Header.Set("Stripe-Signature", fmt.Sprintf("t=%d,v1=%s", ts, hex.EncodeToString(mac.Sum(nil))))
		resp, err := http.DefaultClient.Do(req)
		if err != nil || resp.StatusCode != 204 {
			t.Fatalf("webhook %s = %v %v", typ, resp, err)
		}
	}
	end := h.now.Add(30 * 24 * time.Hour)
	send("customer.subscription.created", "active", end)
	send("customer.subscription.updated", "active", end) // the same period isn't paid twice
	h.do("GET", "/v1/posts/"+id, bob, nil, 200)
	h.do("GET", "/v1/posts/"+fans["id"].(string), bob, nil, 200) // subscribers see followers-only cards too
	if e := h.do("GET", "/v1/me/earnings", ada, nil, 200)["earnings"].(map[string]any); e["total_cents"] != 317.0 || e["subscribers"] != 1.0 ||
		list(e, "recent")[0].(map[string]any)["kind"] != "subscription" {
		t.Fatalf("earnings = %v", e)
	}
	// Renewal: a new period is a new payment.
	send("customer.subscription.updated", "active", end.Add(30*24*time.Hour))
	if e := h.do("GET", "/v1/me/earnings", ada, nil, 200)["earnings"].(map[string]any); e["total_cents"] != 634.0 {
		t.Fatalf("earnings after renewal = %v", e)
	}
	subs := list(h.do("GET", "/v1/me/subscriptions", bob, nil, 200), "subscriptions")
	if len(subs) != 1 || subs[0].(map[string]any)["renews"] != true || subs[0].(map[string]any)["active"] != true {
		t.Fatalf("subscriptions = %v", subs)
	}
	// Cancelling stops renewal; access lasts to the period end.
	if sub := h.do("DELETE", "/v1/users/"+adaHandle+"/subscription", bob, nil, 200); sub["renews"] != false {
		t.Fatalf("cancel = %v", sub)
	}
	if paths[len(paths)-1] != "/v1/subscriptions/sub_1" {
		t.Fatalf("stripe calls = %v", paths)
	}
	h.do("GET", "/v1/posts/"+id, bob, nil, 200)
	// Once it ends, the card locks again.
	send("customer.subscription.deleted", "canceled", h.now.Add(-time.Hour))
	h.do("GET", "/v1/posts/"+id, bob, nil, 404)
}
