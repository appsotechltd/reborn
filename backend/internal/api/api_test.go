package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/agent"
	"github.com/appsotechltd/reborn/backend/internal/auth"
	"github.com/appsotechltd/reborn/backend/internal/cache"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/db"
	"github.com/appsotechltd/reborn/backend/internal/store"
	"github.com/jackc/pgx/v5"
)

// These tests need a Postgres with pgvector. Set TEST_DATABASE_URL to a
// database whose user can CREATE DATABASE; each run gets a throwaway database.
// TEST_REDIS_URL is optional.

type fakeAgent struct{ st *store.Store }

func (f fakeAgent) Chat(ctx context.Context, h []agent.Message) (agent.Reply, error) {
	if len(h) == 0 || h[len(h)-1].Role != "user" {
		return agent.Reply{}, agent.ErrBadConversation
	}
	c, err := f.st.GetCard(ctx, "nhs-sleep-tips--01")
	if err != nil {
		return agent.Reply{}, err
	}
	return agent.Reply{Text: "Keep a steady wake time [nhs-sleep-tips--01].", Citations: []store.Card{c}}, nil
}

type harness struct {
	t   *testing.T
	srv *httptest.Server
	st  *store.Store
	now time.Time
	api *Server
}

func setup(t *testing.T) *harness {
	t.Helper()
	base := os.Getenv("TEST_DATABASE_URL")
	if base == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	admin, err := pgx.Connect(ctx, base)
	if err != nil {
		t.Fatal(err)
	}
	name := fmt.Sprintf("reborn_test_%d", time.Now().UnixNano())
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse(base)
	u.Path = "/" + name
	pool, err := db.Open(ctx, u.String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		pool.Close()
		_, _ = admin.Exec(context.Background(), "DROP DATABASE "+name+" WITH (FORCE)")
		_ = admin.Close(context.Background())
	})
	if _, err := db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	st := store.New(pool)
	if err := st.EnsureTopics(ctx); err != nil {
		t.Fatal(err)
	}
	lib, ps, err := content.LoadDir(filepath.Join("..", "..", "testdata", "library"))
	if err != nil {
		t.Fatal(err)
	}
	// Fixtures are small on purpose, so the card-count warning is expected.
	for _, p := range ps {
		if !p.Warning {
			t.Fatalf("fixtures: %v", ps)
		}
	}
	res, err := st.Seed(ctx, lib)
	if err != nil {
		t.Fatal(err)
	}
	if res.Cards != 9 || res.Changed != 9 {
		t.Fatalf("seed = %+v", res)
	}
	res, err = st.Seed(ctx, lib)
	if err != nil || res.Changed != 0 {
		t.Fatalf("reseed = %+v, %v", res, err)
	}
	var c *cache.Cache
	if ru := os.Getenv("TEST_REDIS_URL"); ru != "" {
		if c, err = cache.Open(ctx, ru); err != nil {
			t.Fatal(err)
		}
		c.R.FlushDB(ctx)
	}
	h := &harness{t: t, st: st, now: time.Date(2026, 10, 10, 9, 0, 0, 0, time.UTC)}
	h.api = &Server{Store: st, Cache: c, Tokens: auth.NewTokens("test"), Agent: fakeAgent{st}, AgentHourly: 3, CORSOrigins: "*",
		Now: func() time.Time { return h.now }}
	h.srv = httptest.NewServer(h.api.Handler())
	t.Cleanup(h.srv.Close)
	return h
}

func (h *harness) do(method, path, token string, body any, want int) map[string]any {
	h.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, h.srv.URL+path, r)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		h.t.Fatal(err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != want {
		h.t.Fatalf("%s %s = %d, want %d: %s", method, path, resp.StatusCode, want, raw)
	}
	out := map[string]any{}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &out); err != nil {
			h.t.Fatalf("%s %s: bad JSON %s", method, path, raw)
		}
	}
	return out
}

func (h *harness) register(email string) string {
	out := h.do("POST", "/v1/auth/register", "", map[string]any{"email": email, "password": "password1", "display_name": "Ada"}, 201)
	return out["token"].(string)
}

func list(m map[string]any, key string) []any {
	v, _ := m[key].([]any)
	return v
}

func ids(cards []any) []string {
	var out []string
	for _, c := range cards {
		out = append(out, c.(map[string]any)["id"].(string))
	}
	return out
}

func TestPublicBrowsing(t *testing.T) {
	h := setup(t)
	h.do("GET", "/healthz", "", nil, 200)

	topics := list(h.do("GET", "/v1/topics", "", nil, 200), "topics")
	if len(topics) != 12 {
		t.Fatalf("topics = %v", topics)
	}
	counts := map[string]float64{}
	for _, tp := range topics {
		m := tp.(map[string]any)
		counts[m["slug"].(string)] = m["card_count"].(float64)
	}
	if counts["health"] != 3 || counts["mindfulness"] != 2 {
		t.Fatalf("counts = %v", counts)
	}

	page1 := h.do("GET", "/v1/feed?limit=5", "", nil, 200)
	page2 := h.do("GET", "/v1/feed?limit=5&cursor="+page1["next_cursor"].(string), "", nil, 200)
	all := append(ids(list(page1, "cards")), ids(list(page2, "cards"))...)
	seen := map[string]bool{}
	for _, id := range all {
		seen[id] = true
	}
	if len(all) != 9 || len(seen) != 9 || page2["next_cursor"] != nil {
		t.Fatalf("feed pages = %v, next %v", all, page2["next_cursor"])
	}
	for _, id := range ids(list(h.do("GET", "/v1/feed?topics=health", "", nil, 200), "cards")) {
		if !strings.HasPrefix(id, "nhs-") {
			t.Fatalf("topic filter leaked %s", id)
		}
	}

	card := h.do("GET", "/v1/cards/nhs-sleep-tips--01", "", nil, 200)
	if card["credit"] != "Source: NHS, How to fall asleep faster and sleep better, Open Government Licence v3.0" {
		t.Fatalf("credit = %v", card["credit"])
	}
	if card["disclaimer"] != content.HealthDisclaimer || card["health"] != true {
		t.Fatalf("health card missing disclaimer: %v", card)
	}
	if src := card["source"].(map[string]any); src["licence"] != "ogl-3.0" || src["url"] == "" {
		t.Fatalf("source = %v", src)
	}
	stoic := h.do("GET", "/v1/cards/meditations-marcus-aurelius--01", "", nil, 200)
	if stoic["disclaimer"] != nil || stoic["quiz"] == nil || stoic["quote"] == nil {
		t.Fatalf("stoic card = %v", stoic)
	}
	h.do("GET", "/v1/cards/nope--01", "", nil, 404)

	got := ids(list(h.do("GET", "/v1/cards?ids=fixture-psychology-notes--02,nhs-sleep-tips--03", "", nil, 200), "cards"))
	if strings.Join(got, ",") != "fixture-psychology-notes--02,nhs-sleep-tips--03" {
		t.Fatalf("cards by ids = %v", got)
	}

	src := h.do("GET", "/v1/sources/meditations-marcus-aurelius", "", nil, 200)
	if len(list(src, "cards")) != 3 || src["source"].(map[string]any)["translator"] != "George Long" {
		t.Fatalf("source page = %v", src)
	}

	srcs := list(h.do("GET", "/v1/sources?topic=health", "", nil, 200), "sources")
	if len(srcs) != 1 || srcs[0].(map[string]any)["id"] != "nhs-sleep-tips" || srcs[0].(map[string]any)["card_count"].(float64) != 3 {
		t.Fatalf("sources = %v", srcs)
	}
	if n := len(list(h.do("GET", "/v1/sources", "", nil, 200), "sources")); n != 3 {
		t.Fatalf("all sources = %d", n)
	}
	sm := h.do("GET", "/v1/sitemap", "", nil, 200)
	if len(list(sm, "cards")) != 9 || len(list(sm, "sources")) != 3 || len(list(sm, "topics")) != 12 {
		t.Fatalf("sitemap = %v", sm)
	}

	found := ids(list(h.do("GET", "/v1/search?q="+url.QueryEscape("how do I sleep better"), "", nil, 200), "cards"))
	if len(found) == 0 || !strings.HasPrefix(found[0], "nhs-sleep-tips") {
		t.Fatalf("search = %v", found)
	}
	if len(list(h.do("GET", "/v1/search?q=caffeine&topic=psychology", "", nil, 200), "cards")) != 0 {
		t.Fatal("search topic filter ignored")
	}
	h.do("GET", "/v1/search?q=", "", nil, 400)
	if n := len(list(h.do("GET", "/v1/search?topic=health", "", nil, 200), "cards")); n != 3 {
		t.Fatalf("topic-only search = %d cards", n)
	}

	d1 := h.do("GET", "/v1/daily", "", nil, 200)
	d2 := h.do("GET", "/v1/daily", "", nil, 200)
	if d1["date"] != "2026-10-10" || d1["card"].(map[string]any)["id"] != d2["card"].(map[string]any)["id"] {
		t.Fatalf("daily not stable: %v %v", d1, d2)
	}
}

func TestAccountFeedAndStashes(t *testing.T) {
	h := setup(t)
	tok := h.register("ada@example.com")
	h.do("POST", "/v1/auth/register", "", map[string]any{"email": "ADA@example.com", "password": "password1"}, 409)
	h.do("POST", "/v1/auth/login", "", map[string]any{"email": "ada@example.com", "password": "wrong-pass"}, 401)
	tok2 := h.do("POST", "/v1/auth/login", "", map[string]any{"email": "Ada@Example.com", "password": "password1"}, 200)["token"].(string)
	h.do("GET", "/v1/me", tok2, nil, 200)
	h.do("GET", "/v1/me", "", nil, 401)
	h.do("GET", "/v1/me", "bad", nil, 401)

	me := h.do("PATCH", "/v1/me", tok, map[string]any{"topics": []string{"mindfulness"}}, 200)
	if fmt.Sprint(me["topics"]) != "[mindfulness]" {
		t.Fatalf("topics = %v", me["topics"])
	}
	h.do("PATCH", "/v1/me", tok, map[string]any{"topics": []string{"cooking"}}, 400)
	feed := ids(list(h.do("GET", "/v1/feed", tok, nil, 200), "cards"))
	if len(feed) != 2 {
		t.Fatalf("personal feed = %v", feed)
	}
	h.do("POST", "/v1/cards/"+feed[0]+"/view", tok, nil, 204)
	feed2 := ids(list(h.do("GET", "/v1/feed", tok, nil, 200), "cards"))
	if feed2[1] != feed[0] {
		t.Fatalf("read card not moved to the end: %v -> %v", feed, feed2)
	}
	if id := h.do("GET", "/v1/daily", tok, nil, 200)["card"].(map[string]any)["id"].(string); !strings.HasPrefix(id, "meditations") {
		t.Fatalf("daily ignores topics: %s", id)
	}

	st := h.do("POST", "/v1/stashes", tok, map[string]any{"name": "Calm"}, 201)
	sid := st["id"].(string)
	h.do("POST", "/v1/stashes", tok, map[string]any{"name": "Calm"}, 409)
	h.do("POST", "/v1/stashes", tok, map[string]any{"name": "  "}, 400)
	h.do("PUT", "/v1/stashes/"+sid+"/cards/meditations-marcus-aurelius--02", tok, nil, 204)
	h.do("PUT", "/v1/stashes/"+sid+"/cards/meditations-marcus-aurelius--02", tok, nil, 204)
	h.do("PUT", "/v1/stashes/"+sid+"/cards/nope--01", tok, nil, 404)
	got := h.do("GET", "/v1/stashes/"+sid, tok, nil, 200)
	if len(list(got, "cards")) != 1 || got["stash"].(map[string]any)["card_count"].(float64) != 1 {
		t.Fatalf("stash = %v", got)
	}
	if len(list(h.do("GET", "/v1/stashes", tok, nil, 200), "stashes")) != 1 {
		t.Fatal("stash list")
	}
	h.do("PATCH", "/v1/stashes/"+sid, tok, map[string]any{"name": "Calm mind"}, 200)

	// Another user cannot see or change it.
	other := h.register("bob@example.com")
	h.do("GET", "/v1/stashes/"+sid, other, nil, 404)
	h.do("PUT", "/v1/stashes/"+sid+"/cards/nhs-sleep-tips--01", other, nil, 404)
	h.do("DELETE", "/v1/stashes/"+sid, other, nil, 404)
	h.do("GET", "/v1/stashes/not-a-uuid", tok, nil, 404)

	// Stashing enrolled the card in review, due tomorrow.
	if due := h.do("GET", "/v1/review/due", tok, nil, 200); due["due_count"].(float64) != 0 {
		t.Fatalf("due today = %v", due)
	}
	h.now = h.now.Add(25 * time.Hour)
	due := h.do("GET", "/v1/review/due", tok, nil, 200)
	if due["due_count"].(float64) != 1 {
		t.Fatalf("due tomorrow = %v", due)
	}
	res := h.do("POST", "/v1/review/meditations-marcus-aurelius--02", tok, map[string]any{"grade": "good"}, 200)
	if res["interval_days"].(float64) != 1 || res["reps"].(float64) != 1 {
		t.Fatalf("grade = %v", res)
	}
	h.do("POST", "/v1/review/meditations-marcus-aurelius--02", tok, map[string]any{"grade": "meh"}, 400)
	if due := h.do("GET", "/v1/review/due", tok, nil, 200); due["due_count"].(float64) != 0 {
		t.Fatalf("still due after grading = %v", due)
	}

	quiz := list(h.do("GET", "/v1/quiz?limit=20", tok, nil, 200), "cards")
	if len(quiz) == 0 || quiz[0].(map[string]any)["id"] != "meditations-marcus-aurelius--02" {
		t.Fatalf("quiz should prefer reviewed cards: %v", ids(quiz))
	}
	for _, c := range quiz {
		if c.(map[string]any)["quiz"] == nil {
			t.Fatal("quiz card without quiz")
		}
	}

	h.do("DELETE", "/v1/stashes/"+sid+"/cards/meditations-marcus-aurelius--02", tok, nil, 204)
	h.do("DELETE", "/v1/stashes/"+sid, tok, nil, 204)
}

func TestContributionsAndModeration(t *testing.T) {
	h := setup(t)
	tok := h.register("writer@example.com")
	mod := h.register("mod@example.com")
	if err := h.st.SetRole(context.Background(), "mod@example.com", "moderator"); err != nil {
		t.Fatal(err)
	}
	idea := map[string]any{
		"source":   map[string]any{"title": "Deep Work", "authors": []string{"Cal Newport"}, "url": "https://calnewport.com/deep-work", "kind": "book"},
		"topic":    "productivity",
		"title":    "Protect a daily block of deep focus",
		"body":     strings.Repeat("Focus on one demanding task without switching. ", 6),
		"apply_it": "Block 90 minutes tomorrow morning for one task, with notifications off.",
	}
	bad := map[string]any{}
	for k, v := range idea {
		bad[k] = v
	}
	bad["body"] = "too short"
	h.do("POST", "/v1/contributions", tok, bad, 400)

	c := h.do("POST", "/v1/contributions", tok, idea, 201)
	if c["status"] != "pending" {
		t.Fatalf("contribution = %v", c)
	}
	second := h.do("POST", "/v1/contributions", tok, idea, 201)
	if len(list(h.do("GET", "/v1/contributions/mine", tok, nil, 200), "contributions")) != 2 {
		t.Fatal("mine")
	}

	h.do("GET", "/v1/moderation/queue", tok, nil, 403)
	if len(list(h.do("GET", "/v1/moderation/queue", mod, nil, 200), "contributions")) != 2 {
		t.Fatal("queue")
	}
	approved := h.do("POST", "/v1/moderation/"+c["id"].(string)+"/approve", mod, map[string]any{"note": "Nice"}, 200)
	cardID, _ := approved["card_id"].(string)
	if approved["status"] != "approved" || !strings.HasSuffix(cardID, "--01") {
		t.Fatalf("approved = %v", approved)
	}
	h.do("POST", "/v1/moderation/"+c["id"].(string)+"/approve", mod, nil, 409)
	card := h.do("GET", "/v1/cards/"+cardID, "", nil, 200)
	if src := card["source"].(map[string]any); src["licence"] != "original-summary" || src["url"] != "https://calnewport.com/deep-work" {
		t.Fatalf("contributed card source = %v", src)
	}
	if card["quote"] != nil {
		t.Fatal("contributed card has a quote")
	}
	// A second idea from the same source lands on the same source page.
	approved2 := h.do("POST", "/v1/moderation/"+second["id"].(string)+"/approve", mod, nil, 200)
	if want := strings.TrimSuffix(cardID, "--01") + "--02"; approved2["card_id"] != want {
		t.Fatalf("second card id = %v, want %s", approved2["card_id"], want)
	}

	third := h.do("POST", "/v1/contributions", tok, idea, 201)
	h.do("POST", "/v1/moderation/"+third["id"].(string)+"/reject", mod, map[string]any{"note": ""}, 400)
	rej := h.do("POST", "/v1/moderation/"+third["id"].(string)+"/reject", mod, map[string]any{"note": "Duplicate"}, 200)
	if rej["status"] != "rejected" || rej["moderator_note"] != "Duplicate" {
		t.Fatalf("rejected = %v", rej)
	}
	h.do("POST", "/v1/moderation/"+third["id"].(string)+"/reject", mod, map[string]any{"note": "again"}, 409)
	h.do("POST", "/v1/moderation/00000000-0000-0000-0000-000000000000/reject", mod, map[string]any{"note": "x"}, 404)
}

func TestAgentEndpoint(t *testing.T) {
	h := setup(t)
	tok := h.register("asker@example.com")
	msg := map[string]any{"messages": []map[string]string{{"role": "user", "content": "How can I sleep better?"}}}
	h.do("POST", "/v1/agent/chat", "", msg, 401)
	out := h.do("POST", "/v1/agent/chat", tok, msg, 200)
	if !strings.Contains(out["reply"].(string), "[nhs-sleep-tips--01]") || len(list(out, "citations")) != 1 {
		t.Fatalf("chat = %v", out)
	}
	h.do("POST", "/v1/agent/chat", tok, map[string]any{"messages": []any{}}, 400)

	if h.api.Cache != nil {
		h.do("POST", "/v1/agent/chat", tok, msg, 200) // third request this hour
		h.do("POST", "/v1/agent/chat", tok, msg, 429) // limit is 3 per hour in tests
	}

	h.api.Agent = nil
	h.do("POST", "/v1/agent/chat", tok, msg, 503)
}
