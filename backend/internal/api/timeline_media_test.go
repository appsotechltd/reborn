package api

import (
	"context"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/cardimages"
	"github.com/appsotechltd/reborn/backend/internal/explainers"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

func sortedIDs(ps []map[string]any) string {
	ids := postIDsOf(ps)
	sort.Strings(ids)
	return strings.Join(ids, " ")
}

func TestTimelineMediaFilter(t *testing.T) {
	h := setup(t)
	store.SetExplainers(explainers.Set{
		"meditations-marcus-aurelius--01": {Kind: "animated", VideoURL: "/media/explainers/meditations-marcus-aurelius--01.mp4"},
		"nhs-sleep-tips--02":              {Kind: "animated", VideoURL: "/media/explainers/nhs-sleep-tips--02.mp4"},
	})
	store.SetImages(cardimages.Set{
		"meditations-marcus-aurelius--01": {URL: "https://media.example.com/a.webp", Type: "illustration"},
		"nhs-sleep-tips--01":              {URL: "https://media.example.com/b.webp", Type: "illustration"},
	})
	t.Cleanup(func() {
		store.SetExplainers(nil)
		store.SetImages(nil)
	})
	tok, _ := h.registerAs("ada@example.com", "Ada Lovelace")
	bob, _ := h.registerAs("bob@example.com", "Bob")

	// Member cards: one with an illustrated video, one with a picture, one with neither.
	member := func(title, media string) string {
		c := h.do("POST", "/v1/me/cards", bob, map[string]any{"title": title, "body": "Some words.", "topic": "psychology"}, 201)
		if media != "" {
			if _, err := h.st.DB.Exec(context.Background(), `UPDATE cards SET media = $2::jsonb WHERE id = $1`, c["id"], media); err != nil {
				t.Fatal(err)
			}
		}
		return c["id"].(string)
	}
	memberVideo := member("A video card", `{"video": {"kind": "illustrated", "scenes": [], "audio_url": "https://media.example.com/v.mp3"}}`)
	memberImage := member("A picture card", `{"image": {"url": "https://media.example.com/m.webp"}}`)
	member("A text card", "")

	if all := posts(h.do("GET", "/v1/timeline?limit=50", tok, nil, 200)); len(all) != 12 {
		t.Fatalf("unfiltered timeline = %v", postIDsOf(all))
	}
	if all := posts(h.do("GET", "/v1/timeline?limit=50&media=all", tok, nil, 200)); len(all) != 12 {
		t.Fatalf("media=all timeline = %v", postIDsOf(all))
	}
	h.do("GET", "/v1/timeline?media=audio", tok, nil, 400)

	videos := posts(h.do("GET", "/v1/timeline?limit=50&media=video", tok, nil, 200))
	if got, want := sortedIDs(videos), strings.Join(sortStrings(memberVideo, "meditations-marcus-aurelius--01", "nhs-sleep-tips--02"), " "); got != want {
		t.Fatalf("videos = %s, want %s", got, want)
	}
	for _, p := range videos {
		c := p["card"].(map[string]any)
		if c["explainer"] == nil && c["video"] == nil {
			t.Fatalf("video post without a video: %v", p["id"])
		}
	}
	images := posts(h.do("GET", "/v1/timeline?limit=50&media=image", tok, nil, 200))
	if got, want := sortedIDs(images), strings.Join(sortStrings(memberImage, "meditations-marcus-aurelius--01", "nhs-sleep-tips--01"), " "); got != want {
		t.Fatalf("images = %s, want %s", got, want)
	}
	for _, p := range images {
		if p["card"].(map[string]any)["image"] == nil {
			t.Fatalf("image post without a picture: %v", p["id"])
		}
	}

	// Signed out works too, and topics still narrow it.
	if anon := posts(h.do("GET", "/v1/timeline?media=video&topics=health", "", nil, 200)); sortedIDs(anon) != "nhs-sleep-tips--02" {
		t.Fatalf("signed-out health videos = %v", postIDsOf(anon))
	}

	// Pages follow the filter without overlapping, and summary posts stay out.
	page1 := h.do("GET", "/v1/timeline?limit=2&media=video&with=summaries", tok, nil, 200)
	cursor, _ := page1["next_cursor"].(string)
	if len(posts(page1)) != 2 || cursor == "" {
		t.Fatalf("page 1 = %v", page1)
	}
	page2 := h.do("GET", "/v1/timeline?limit=2&media=video&with=summaries&cursor="+cursor, tok, nil, 200)
	both := append(posts(page1), posts(page2)...)
	if sortedIDs(both) != sortedIDs(videos) || page2["next_cursor"] != nil {
		t.Fatalf("pages = %v then %v", postIDsOf(posts(page1)), page2)
	}
	for _, p := range both {
		if p["card"] == nil {
			t.Fatalf("non-card item in a filtered timeline: %v", p)
		}
	}

	// Unseen first still holds.
	h.do("POST", "/v1/seen", tok, map[string]any{"post_ids": []string{"nhs-sleep-tips--02"}}, 204)
	h.now = h.now.Add(time.Minute)
	reopened := posts(h.do("GET", "/v1/timeline?limit=50&media=video", tok, nil, 200))
	if len(reopened) != 3 || reopened[2]["id"] != "nhs-sleep-tips--02" {
		t.Fatalf("seen video not last: %v", postIDsOf(reopened))
	}
}

func sortStrings(xs ...string) []string {
	sort.Strings(xs)
	return xs
}
