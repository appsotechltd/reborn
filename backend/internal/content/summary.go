package content

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"
)

// A summary is one post for a whole book or topic, read part by part; each
// part is an existing card. Every source with at least MinSummaryParts cards
// gets a book summary of all its cards, built at seed time. Topic summaries
// are hand-picked runs of cards from several sources, one file each in
// content/summaries/<id>.json.
const (
	MinSummaryParts = 5
	MaxSummaryParts = 50
)

// TopicSummary is one content/summaries/<id>.json file.
type TopicSummary struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Topic       string   `json:"topic"`
	Cards       []string `json:"cards"`
}

// SummaryDir is where topic summaries live next to a library directory:
// content/library -> content/summaries.
func SummaryDir(libraryDir string) string {
	return filepath.Join(filepath.Dir(filepath.Clean(libraryDir)), "summaries")
}

// ValidateSummary checks a topic summary against the loaded library.
func ValidateSummary(name string, s TopicSummary, lib Library) []Problem {
	var ps []Problem
	add := func(field, msg string) { ps = append(ps, Problem{File: name, Field: field, Message: msg}) }
	if !slugRe.MatchString(s.ID) || len(s.ID) > 80 {
		add("id", "must be a lowercase slug of at most 80 chars")
	}
	if want := strings.TrimSuffix(name, ".json"); s.ID != "" && s.ID != want {
		add("id", fmt.Sprintf("must equal the file name %q", want))
	}
	if n := utf8.RuneCountInString(strings.TrimSpace(s.Title)); n == 0 || n > 90 {
		add("title", "is required and at most 90 chars")
	}
	if n := utf8.RuneCountInString(strings.TrimSpace(s.Description)); n == 0 || n > 300 {
		add("description", "is required and at most 300 chars")
	}
	if !IsTopic(s.Topic) {
		add("topic", fmt.Sprintf("%q is not a known topic", s.Topic))
	}
	if len(s.Cards) < MinSummaryParts || len(s.Cards) > MaxSummaryParts {
		add("cards", fmt.Sprintf("has %d cards; a summary needs %d-%d", len(s.Cards), MinSummaryParts, MaxSummaryParts))
	}
	known := map[string]bool{}
	for _, f := range lib.Files {
		if f.Source.ID == s.ID {
			add("id", "is already a source id, whose book summary uses it")
		}
		for _, c := range f.Cards {
			known[c.ID] = true
		}
	}
	seen := map[string]bool{}
	for _, id := range s.Cards {
		if seen[id] {
			ps = append(ps, Problem{File: name, Card: id, Field: "cards", Message: "listed twice"})
		}
		seen[id] = true
		if !known[id] {
			ps = append(ps, Problem{File: name, Card: id, Field: "cards", Message: "is not a card in the library"})
		}
	}
	return ps
}

// LoadSummaries reads and validates every topic summary in dir against lib.
// A missing directory means no topic summaries. Files with errors are skipped
// and reported.
func LoadSummaries(dir string, lib Library) ([]TopicSummary, []Problem, error) {
	paths, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, nil, err
	}
	sort.Strings(paths)
	var out []TopicSummary
	var all []Problem
	for _, p := range paths {
		name := filepath.Base(p)
		raw, err := os.ReadFile(p)
		if err != nil {
			return nil, nil, err
		}
		var s TopicSummary
		dec := json.NewDecoder(strings.NewReader(string(raw)))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&s); err != nil {
			all = append(all, Problem{File: name, Message: "invalid JSON: " + err.Error()})
			continue
		}
		ps := ValidateSummary(name, s, lib)
		all = append(all, ps...)
		if !hasError(ps) {
			out = append(out, s)
		}
	}
	return out, all, nil
}
