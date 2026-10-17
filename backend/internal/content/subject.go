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

// A subject is a short course: guides meant to be followed one after the
// other, such as Communication Clarity under Life Guides. Each guide is a
// library source whose book summary is the guide's reader, so a subject is an
// ordered list of those summaries. One file each in content/subjects/<id>.json.
const (
	MinSubjectGuides = 2
	MaxSubjectGuides = 20
)

// Subject is one content/subjects/<id>.json file.
type Subject struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	// Topics are the categories whose pages list the subject, main one first.
	Topics []string `json:"topics"`
	// Guides are source ids in the order a reader should follow them.
	Guides []string `json:"guides"`
}

// SubjectDir is where subjects live next to a library directory:
// content/library -> content/subjects.
func SubjectDir(libraryDir string) string {
	return filepath.Join(filepath.Dir(filepath.Clean(libraryDir)), "subjects")
}

// ValidateSubject checks a subject against the loaded library.
func ValidateSubject(name string, s Subject, lib Library) []Problem {
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
	if len(s.Topics) == 0 {
		add("topics", "needs at least one topic")
	}
	seenTopic := map[string]bool{}
	for _, t := range s.Topics {
		if !IsTopic(t) {
			add("topics", fmt.Sprintf("%q is not a known topic", t))
		}
		if seenTopic[t] {
			add("topics", fmt.Sprintf("%q is listed twice", t))
		}
		seenTopic[t] = true
	}
	if len(s.Guides) < MinSubjectGuides || len(s.Guides) > MaxSubjectGuides {
		add("guides", fmt.Sprintf("has %d guides; a subject needs %d-%d", len(s.Guides), MinSubjectGuides, MaxSubjectGuides))
	}
	cards := map[string]int{}
	for _, f := range lib.Files {
		cards[f.Source.ID] = len(f.Cards)
	}
	seen := map[string]bool{}
	for _, id := range s.Guides {
		if seen[id] {
			add("guides", fmt.Sprintf("%q is listed twice", id))
		}
		seen[id] = true
		n, ok := cards[id]
		if !ok {
			add("guides", fmt.Sprintf("%q is not a source in the library", id))
		} else if n < MinSummaryParts {
			add("guides", fmt.Sprintf("%q has %d cards; a guide needs %d to have a reader", id, n, MinSummaryParts))
		}
	}
	return ps
}

// LoadSubjects reads and validates every subject in dir against lib. A
// missing directory means no subjects. Files with errors are skipped and
// reported.
func LoadSubjects(dir string, lib Library) ([]Subject, []Problem, error) {
	paths, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, nil, err
	}
	sort.Strings(paths)
	var out []Subject
	var all []Problem
	for _, p := range paths {
		name := filepath.Base(p)
		raw, err := os.ReadFile(p)
		if err != nil {
			return nil, nil, err
		}
		var s Subject
		dec := json.NewDecoder(strings.NewReader(string(raw)))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&s); err != nil {
			all = append(all, Problem{File: name, Message: "invalid JSON: " + err.Error()})
			continue
		}
		ps := ValidateSubject(name, s, lib)
		all = append(all, ps...)
		if !hasError(ps) {
			out = append(out, s)
		}
	}
	return out, all, nil
}
