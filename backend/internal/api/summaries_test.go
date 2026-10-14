package api

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// seedSummaries adds a six-card book (enough for a book summary; the fixture
// sources are too short) and a topic summary drawn from two sources.
func (h *harness) seedSummaries(withTopic bool) {
	h.t.Helper()
	lib, _, err := content.LoadDir(filepath.Join("..", "..", "testdata", "library"))
	if err != nil {
		h.t.Fatal(err)
	}
	base := lib.Files[1] // meditations
	book := content.File{Source: base.Source}
	book.Source.ID, book.Source.Title = "test-book", "Test Book"
	for i := 1; i <= 6; i++ {
		c := base.Cards[(i-1)%len(base.Cards)]
		c.ID = fmt.Sprintf("test-book--%02d", i)
		c.Title = fmt.Sprintf("Part %d", i)
		book.Cards = append(book.Cards, c)
	}
	lib.Files = append(lib.Files, book)
	if withTopic {
		lib.Summaries = []content.TopicSummary{{ID: "calm-sleep", Title: "Calm and sleep", Description: "Rest well.", Topic: "health",
			Cards: []string{"nhs-sleep-tips--01", "meditations-marcus-aurelius--01", "nhs-sleep-tips--02", "nhs-sleep-tips--03", "meditations-marcus-aurelius--02"}}}
	}
	res, err := h.st.Seed(context.Background(), lib)
	if err != nil {
		h.t.Fatal(err)
	}
	if want := 1 + len(lib.Summaries); res.Summaries != want {
		h.t.Fatalf("seeded %d summaries, want %d", res.Summaries, want)
	}
}

func summaryIDs(posts []any) (out []string, at []int) {
	for i, p := range posts {
		m := p.(map[string]any)
		if m["kind"] == "summary" {
			out = append(out, m["summary"].(map[string]any)["id"].(string))
			at = append(at, i)
		}
	}
	return out, at
}

func TestSummaries(t *testing.T) {
	h := setup(t)
	h.seedSummaries(true)

	all := list(h.do("GET", "/v1/summaries", "", nil, 200), "summaries")
	if got := ids(all); len(got) != 2 || got[0] != "calm-sleep" || got[1] != "test-book" {
		t.Fatalf("summaries = %v", got)
	}
	if got := ids(list(h.do("GET", "/v1/summaries?kind=book", "", nil, 200), "summaries")); len(got) != 1 || got[0] != "test-book" {
		t.Fatalf("books = %v", got)
	}
	if got := ids(list(h.do("GET", "/v1/summaries?source=nhs-sleep-tips", "", nil, 200), "summaries")); len(got) != 1 || got[0] != "calm-sleep" {
		t.Fatalf("by source = %v", got)
	}
	h.do("GET", "/v1/summaries?topic=cooking", "", nil, 400)

	book := h.do("GET", "/v1/summaries/test-book", "", nil, 200)
	parts := list(book, "parts")
	if len(parts) != 6 || book["part_count"].(float64) != 6 || book["coverage"] != "full" || book["kind"] != "book" ||
		parts[0].(map[string]any)["id"] != "test-book--01" || book["source"].(map[string]any)["id"] != "test-book" {
		t.Fatalf("book summary = %v", book)
	}
	if book["viewer"] != nil {
		t.Fatalf("anonymous viewer = %v", book["viewer"])
	}
	topic := h.do("GET", "/v1/summaries/calm-sleep", "", nil, 200)
	if topic["coverage"] != "topic" || topic["source_count"].(float64) != 2 || topic["source"] != nil ||
		len(list(topic, "parts")) != 5 || topic["topic_name"] != "Health & Wellness" {
		t.Fatalf("topic summary = %v", topic)
	}
	h.do("GET", "/v1/summaries/nope", "", nil, 404)

	if got := h.do("GET", "/v1/sources/test-book", "", nil, 200)["summary_id"]; got != "test-book" {
		t.Fatalf("source summary_id = %v", got)
	}
	if got := h.do("GET", "/v1/sources/nhs-sleep-tips", "", nil, 200)["summary_id"]; got != nil {
		t.Fatalf("short source summary_id = %v", got)
	}
	if got := ids(list(h.do("GET", "/v1/sitemap", "", nil, 200), "summaries")); len(got) != 2 {
		t.Fatalf("sitemap summaries = %v", got)
	}

	// The timeline only carries summaries when asked, one before every 6th card post.
	plain := list(h.do("GET", "/v1/timeline?limit=20", "", nil, 200), "posts")
	if got, _ := summaryIDs(plain); len(got) != 0 || len(plain) != 15 {
		t.Fatalf("plain timeline has %d posts, summaries %v", len(plain), got)
	}
	woven := list(h.do("GET", "/v1/timeline?limit=20&with=summaries", "", nil, 200), "posts")
	got, at := summaryIDs(woven)
	if len(woven) != 17 || len(got) != 2 || got[0] == got[1] || at[0] != 6 || at[1] != 13 {
		t.Fatalf("woven timeline: %d posts, summaries %v at %v", len(woven), got, at)
	}
	// Paging gives the same summaries in the same places.
	var paged []string
	cursor := ""
	for i := 0; i < 4; i++ {
		page := h.do("GET", "/v1/timeline?limit=5&with=summaries"+cursor, "", nil, 200)
		s, _ := summaryIDs(list(page, "posts"))
		paged = append(paged, s...)
		next, _ := page["next_cursor"].(string)
		if next == "" {
			break
		}
		cursor = "&cursor=" + next
	}
	if fmt.Sprint(paged) != fmt.Sprint(got) {
		t.Fatalf("paged summaries %v, want %v", paged, got)
	}

	// Progress: resume where you stopped; finishing sticks; started ones move behind new ones.
	h.do("PUT", "/v1/summaries/test-book/progress", "", map[string]any{"position": 1}, 401)
	tok := h.register("reader@example.com")
	p := h.do("PUT", "/v1/summaries/test-book/progress", tok, map[string]any{"position": 2}, 200)
	if p["position"].(float64) != 2 || p["finished"] != false || p["started"] != true {
		t.Fatalf("progress = %v", p)
	}
	h.do("PUT", "/v1/summaries/test-book/progress", tok, map[string]any{"position": 6}, 400)
	h.do("PUT", "/v1/summaries/test-book/progress", tok, map[string]any{}, 400)
	h.do("PUT", "/v1/summaries/nope/progress", tok, map[string]any{"position": 0}, 404)
	h.do("PUT", "/v1/summaries/test-book/progress", tok, map[string]any{"position": 5, "finished": true}, 200)
	p = h.do("PUT", "/v1/summaries/test-book/progress", tok, map[string]any{"position": 3}, 200)
	if p["position"].(float64) != 3 || p["finished"] != true {
		t.Fatalf("progress after rereading = %v", p)
	}
	v := h.do("GET", "/v1/summaries/test-book", tok, nil, 200)["viewer"].(map[string]any)
	if v["position"].(float64) != 3 || v["finished"] != true || v["started"] != true {
		t.Fatalf("viewer = %v", v)
	}
	if v := h.do("GET", "/v1/summaries/calm-sleep", tok, nil, 200)["viewer"].(map[string]any); v["started"] != false {
		t.Fatalf("unstarted viewer = %v", v)
	}
	h.now = h.now.Add(time.Minute)
	for i := 0; i < 5; i++ { // whatever the day's shuffle, the unread one comes first
		got, _ := summaryIDs(list(h.do("GET", "/v1/timeline?limit=20&with=summaries", tok, nil, 200), "posts"))
		if len(got) != 2 || got[0] != "calm-sleep" {
			t.Fatalf("signed-in timeline summaries = %v", got)
		}
		h.now = h.now.Add(24 * time.Hour)
	}

	// A topic filter keeps summaries to that topic.
	sums, err := h.st.SummaryFeed(context.Background(), store.SummaryFeedParams{Topics: []string{"health"}, TopicsOnly: true,
		Snapshot: h.now, Limit: 10})
	if err != nil || len(sums) != 1 || sums[0].ID != "calm-sleep" {
		t.Fatalf("health summaries = %v, %v", sums, err)
	}

	// A topic summary taken out of the library disappears.
	h.seedSummaries(false)
	h.do("GET", "/v1/summaries/calm-sleep", "", nil, 404)
	if got := ids(list(h.do("GET", "/v1/summaries", "", nil, 200), "summaries")); len(got) != 1 {
		t.Fatalf("after removal = %v", got)
	}
}
