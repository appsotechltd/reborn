package content

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func summaryLib() Library {
	var cards []Card
	for _, id := range []string{"book-a--01", "book-a--02", "book-a--03", "book-a--04", "book-a--05", "book-a--06"} {
		cards = append(cards, Card{ID: id, Topic: "money"})
	}
	return Library{Files: []File{{Source: Source{ID: "book-a"}, Cards: cards}}}
}

func TestValidateSummary(t *testing.T) {
	good := TopicSummary{ID: "money-basics", Title: "Money basics", Description: "Rules that last.", Topic: "money",
		Cards: []string{"book-a--01", "book-a--02", "book-a--03", "book-a--04", "book-a--05"}}
	if ps := ValidateSummary("money-basics.json", good, summaryLib()); len(ps) != 0 {
		t.Fatalf("good summary rejected:\n%s", messages(ps))
	}
	cases := map[string]func(s *TopicSummary){
		"must equal the file name":     func(s *TopicSummary) { s.ID = "other" },
		"already a source id":          func(s *TopicSummary) { s.ID = "book-a" },
		"not a known topic":            func(s *TopicSummary) { s.Topic = "cooking" },
		"a summary needs 5-50":         func(s *TopicSummary) { s.Cards = s.Cards[:4] },
		"listed twice":                 func(s *TopicSummary) { s.Cards = append(s.Cards, "book-a--01") },
		"is not a card in the library": func(s *TopicSummary) { s.Cards = append(s.Cards, "book-b--01") },
		"description":                  func(s *TopicSummary) { s.Description = "" },
	}
	for want, mutate := range cases {
		s := good
		s.Cards = append([]string(nil), good.Cards...)
		mutate(&s)
		name := "money-basics.json"
		if s.ID == "book-a" {
			name = "book-a.json"
		}
		ps := ValidateSummary(name, s, summaryLib())
		if !strings.Contains(messages(ps), want) {
			t.Errorf("%s: got %q", want, messages(ps))
		}
	}
}

func TestLoadSummariesMissingDir(t *testing.T) {
	sums, ps, err := LoadSummaries(filepath.Join(t.TempDir(), "nope"), summaryLib())
	if err != nil || len(sums) != 0 || len(ps) != 0 {
		t.Fatalf("missing dir = %v, %v, %v", sums, ps, err)
	}
}

func TestLoadSummariesSkipsBadFiles(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "bad.json"), []byte(`{"id":"bad","cards":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	sums, ps, err := LoadSummaries(dir, summaryLib())
	if err != nil || len(sums) != 0 || !hasError(ps) {
		t.Fatalf("bad file = %v, %v, %v", sums, ps, err)
	}
}

// TestRepoSummaries validates content/summaries against content/library.
func TestRepoSummaries(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "content", "library")
	lib, _, err := LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	sums, ps, err := LoadSummaries(SummaryDir(dir), lib)
	if err != nil {
		t.Fatal(err)
	}
	if hasError(ps) {
		t.Fatalf("content/summaries has errors:\n%s", messages(ps))
	}
	if len(sums) == 0 {
		t.Fatal("no topic summaries loaded")
	}
}
