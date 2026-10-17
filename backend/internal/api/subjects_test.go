package api

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"

	"github.com/appsotechltd/reborn/backend/internal/content"
)

// seedSubject adds three six-card guides and a subject that follows them in order.
func (h *harness) seedSubject() {
	h.t.Helper()
	lib, _, err := content.LoadDir(filepath.Join("..", "..", "testdata", "library"))
	if err != nil {
		h.t.Fatal(err)
	}
	base := lib.Files[1]
	var guides []string
	for g := 1; g <= 3; g++ {
		f := content.File{Source: base.Source}
		f.Source.ID, f.Source.Title, f.Source.Kind = fmt.Sprintf("guide-%d", g), fmt.Sprintf("Guide %d", g), "guide"
		for i := 1; i <= 6; i++ {
			c := base.Cards[(i-1)%len(base.Cards)]
			c.ID = fmt.Sprintf("%s--%02d", f.Source.ID, i)
			c.Title = fmt.Sprintf("Guide %d part %d", g, i)
			c.Topic = "life-guides"
			f.Cards = append(f.Cards, c)
		}
		lib.Files = append(lib.Files, f)
		guides = append(guides, f.Source.ID)
	}
	lib.Subjects = []content.Subject{{ID: "speak-clearly", Title: "Speak Clearly", Description: "Three guides in order.",
		Topics: []string{"life-guides", "communication"}, Guides: []string{"guide-2", "guide-1", "guide-3"}}}
	if ps := content.ValidateSubject("speak-clearly.json", lib.Subjects[0], lib); len(ps) != 0 {
		h.t.Fatalf("subject problems: %v", ps)
	}
	res, err := h.st.Seed(context.Background(), lib)
	if err != nil {
		h.t.Fatal(err)
	}
	if res.Subjects != 1 {
		h.t.Fatalf("seeded %d subjects", res.Subjects)
	}
}

func TestSubjects(t *testing.T) {
	h := setup(t)
	h.seedSubject()

	for _, topic := range []string{"", "life-guides", "communication"} {
		if got := list(h.do("GET", "/v1/subjects?topic="+topic, "", nil, 200), "subjects"); len(got) != 1 {
			t.Fatalf("subjects in %q = %v", topic, got)
		}
	}
	if got := list(h.do("GET", "/v1/subjects?topic=health", "", nil, 200), "subjects"); len(got) != 0 {
		t.Fatalf("health subjects = %v", got)
	}
	h.do("GET", "/v1/subjects?topic=cooking", "", nil, 400)
	h.do("GET", "/v1/subjects/nope", "", nil, 404)

	sj := h.do("GET", "/v1/subjects/speak-clearly", "", nil, 200)
	gs := ids(list(sj, "guides"))
	if fmt.Sprint(gs) != "[guide-2 guide-1 guide-3]" || sj["guide_count"].(float64) != 3 || sj["part_count"].(float64) != 18 || sj["viewer"] != nil {
		t.Fatalf("subject = %v", sj)
	}

	// Each guide knows its place and the guide after it.
	step := h.do("GET", "/v1/summaries/guide-1", "", nil, 200)["subject"].(map[string]any)
	if step["id"] != "speak-clearly" || step["step"].(float64) != 2 || step["count"].(float64) != 3 ||
		step["next"].(map[string]any)["id"] != "guide-3" {
		t.Fatalf("step = %v", step)
	}
	last := h.do("GET", "/v1/summaries/guide-3", "", nil, 200)["subject"].(map[string]any)
	if last["step"].(float64) != 3 || last["next"] != nil {
		t.Fatalf("last step = %v", last)
	}

	// Progress: next is the first guide not finished, in subject order.
	tok := h.register("learner@example.com")
	v := h.do("GET", "/v1/subjects/speak-clearly", tok, nil, 200)["viewer"].(map[string]any)
	if v["started"] != false || v["finished"].(float64) != 0 || v["next_summary_id"] != "guide-2" || v["done"] != false {
		t.Fatalf("new viewer = %v", v)
	}
	h.do("PUT", "/v1/summaries/guide-2/progress", tok, map[string]any{"position": 5, "finished": true}, 200)
	h.do("PUT", "/v1/summaries/guide-3/progress", tok, map[string]any{"position": 1}, 200)
	v = list(h.do("GET", "/v1/subjects?topic=life-guides", tok, nil, 200), "subjects")[0].(map[string]any)["viewer"].(map[string]any)
	if v["started"] != true || v["finished"].(float64) != 1 || v["next_summary_id"] != "guide-1" {
		t.Fatalf("viewer after one guide = %v", v)
	}
	for _, g := range []string{"guide-1", "guide-3"} {
		h.do("PUT", "/v1/summaries/"+g+"/progress", tok, map[string]any{"position": 5, "finished": true}, 200)
	}
	v = h.do("GET", "/v1/subjects/speak-clearly", tok, nil, 200)["viewer"].(map[string]any)
	if v["done"] != true || v["finished"].(float64) != 3 || v["next_summary_id"] != nil {
		t.Fatalf("finished viewer = %v", v)
	}
}

func TestValidateSubject(t *testing.T) {
	lib, _, err := content.LoadDir(filepath.Join("..", "..", "testdata", "library"))
	if err != nil {
		t.Fatal(err)
	}
	bad := content.Subject{ID: "Bad", Title: "", Description: "x", Topics: []string{"cooking"},
		Guides: []string{"nhs-sleep-tips", "nhs-sleep-tips", "nope"}}
	if ps := content.ValidateSubject("bad.json", bad, lib); len(ps) < 5 {
		t.Fatalf("problems = %v", ps)
	}
}
