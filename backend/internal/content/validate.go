package content

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"
)

var (
	slugRe   = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
	cardIDRe = regexp.MustCompile(`^([a-z0-9]+(?:-[a-z0-9]+)*)--[0-9]{2,3}$`)
	dateRe   = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
	urlRe    = regexp.MustCompile(`^https?://\S+$`)
)

// Problem is one validation finding.
type Problem struct {
	File    string
	Card    string
	Field   string
	Message string
	Warning bool
}

func (p Problem) String() string {
	loc := p.File
	if p.Card != "" {
		loc += " card " + p.Card
	}
	if p.Field != "" {
		loc += " field " + p.Field
	}
	level := "error"
	if p.Warning {
		level = "warning"
	}
	return fmt.Sprintf("%s: %s: %s", level, loc, p.Message)
}

// Each source should have MinCardsPerSource to MaxCardsPerSource cards.
// Fewer is a warning (a short source may not have 30 ideas); more is an error.
const (
	MinCardsPerSource = 30
	MaxCardsPerSource = 50
)

// WordCount counts whitespace-separated words.
func WordCount(s string) int { return len(strings.Fields(s)) }

// ValidateSource checks a source's fields.
func ValidateSource(file string, s Source) []Problem {
	var ps []Problem
	add := func(field, msg string) { ps = append(ps, Problem{File: file, Field: field, Message: msg}) }
	if !slugRe.MatchString(s.ID) || len(s.ID) > 80 {
		add("source.id", "must be a lowercase slug of at most 80 chars")
	}
	if strings.TrimSpace(s.Title) == "" {
		add("source.title", "is required")
	}
	if len(s.Authors) == 0 {
		add("source.authors", "needs at least one author")
	}
	for _, a := range s.Authors {
		if strings.TrimSpace(a) == "" {
			add("source.authors", "contains an empty name")
		}
	}
	if !contains(Kinds, s.Kind) {
		add("source.kind", fmt.Sprintf("%q is not one of %s", s.Kind, strings.Join(Kinds, ", ")))
	}
	if !urlRe.MatchString(s.URL) {
		add("source.url", "must be an http(s) URL")
	}
	lic := strings.ToLower(s.Licence)
	if strings.Contains(lic, "nc") && lic != "cc0-1.0" {
		add("source.licence", "non-commercial licences are not allowed")
	} else if _, ok := Licences[s.Licence]; !ok {
		add("source.licence", fmt.Sprintf("%q is not an allowed licence code", s.Licence))
	}
	if !urlRe.MatchString(s.LicenceURL) {
		add("source.licence_url", "must be an http(s) URL")
	}
	if strings.TrimSpace(s.Attribution) == "" || utf8.RuneCountInString(s.Attribution) > 300 {
		add("source.attribution", "is required and at most 300 chars")
	}
	if !dateRe.MatchString(s.RetrievedAt) {
		add("source.retrieved_at", "must be YYYY-MM-DD")
	}
	return ps
}

// ValidateCard checks one card against its source.
func ValidateCard(file string, s Source, c Card) []Problem {
	var ps []Problem
	add := func(field, msg string) {
		ps = append(ps, Problem{File: file, Card: c.ID, Field: field, Message: msg})
	}
	m := cardIDRe.FindStringSubmatch(c.ID)
	if m == nil {
		add("id", "must look like <source-id>--NN")
	} else if s.ID != "" && m[1] != s.ID {
		add("id", fmt.Sprintf("must start with %q", s.ID+"--"))
	}
	if !IsTopic(c.Topic) {
		add("topic", fmt.Sprintf("%q is not a known topic", c.Topic))
	}
	if len(c.Tags) > 8 {
		add("tags", "at most 8 tags")
	}
	for _, t := range c.Tags {
		if !slugRe.MatchString(t) {
			add("tags", fmt.Sprintf("%q is not a lowercase slug", t))
		}
	}
	if n := utf8.RuneCountInString(strings.TrimSpace(c.Title)); n == 0 || n > 90 {
		add("title", "is required and at most 90 chars")
	}
	if utf8.RuneCountInString(c.Body) > 1200 {
		add("body", "at most 1200 chars")
	}
	if w := WordCount(c.Body); w < 25 || w > 160 {
		add("body", fmt.Sprintf("has %d words; must be 25-160", w))
	}
	if c.Quote != "" {
		if allowed, ok := Licences[s.Licence]; ok && !allowed {
			add("quote", "quotes are not allowed for "+s.Licence+" sources")
		}
		if utf8.RuneCountInString(c.Quote) > 300 {
			add("quote", "at most 300 chars")
		}
	}
	if n := utf8.RuneCountInString(strings.TrimSpace(c.ApplyIt)); n == 0 || n > 240 {
		add("apply_it", "is required and at most 240 chars")
	}
	if c.Topic == "health" && !c.Health {
		add("health", "must be true when topic is health")
	}
	if q := c.Quiz; q != nil {
		if n := utf8.RuneCountInString(strings.TrimSpace(q.Question)); n == 0 || n > 200 {
			add("quiz.question", "is required and at most 200 chars")
		}
		if len(q.Options) < 2 || len(q.Options) > 4 {
			add("quiz.options", "needs 2-4 options")
		}
		for _, o := range q.Options {
			if n := utf8.RuneCountInString(strings.TrimSpace(o)); n == 0 || n > 120 {
				add("quiz.options", "each option is required and at most 120 chars")
			}
		}
		if q.Answer < 0 || q.Answer >= len(q.Options) {
			add("quiz.answer", "must index into options")
		}
		if utf8.RuneCountInString(q.Explanation) > 300 {
			add("quiz.explanation", "at most 300 chars")
		}
	}
	return ps
}

// ValidateFile checks a whole library file. name is the file's base name.
func ValidateFile(name string, f File) []Problem {
	ps := ValidateSource(name, f.Source)
	if want := strings.TrimSuffix(name, ".json"); f.Source.ID != "" && f.Source.ID != want {
		ps = append(ps, Problem{File: name, Field: "source.id", Message: fmt.Sprintf("must equal the file name %q", want)})
	}
	if len(f.Cards) == 0 {
		ps = append(ps, Problem{File: name, Field: "cards", Message: "needs at least one card"})
	} else if len(f.Cards) > MaxCardsPerSource {
		ps = append(ps, Problem{File: name, Field: "cards", Message: fmt.Sprintf("has %d cards; the most a source may have is %d", len(f.Cards), MaxCardsPerSource)})
	} else if len(f.Cards) < MinCardsPerSource {
		ps = append(ps, Problem{File: name, Field: "cards", Message: fmt.Sprintf("has %d cards; aim for at least %d", len(f.Cards), MinCardsPerSource), Warning: true})
	}
	seen := map[string]bool{}
	for _, c := range f.Cards {
		if seen[c.ID] {
			ps = append(ps, Problem{File: name, Card: c.ID, Field: "id", Message: "duplicate card id"})
		}
		seen[c.ID] = true
		ps = append(ps, ValidateCard(name, f.Source, c)...)
	}
	return ps
}

// Library is a set of loaded library files.
type Library struct {
	Files []File
	// Summaries are the hand-picked topic summaries (see LoadSummaries).
	Summaries []TopicSummary
	// Subjects are the ordered courses of guides (see LoadSubjects).
	Subjects []Subject
}

// LoadDir reads and validates every *.json file in dir. Files with errors are
// skipped and reported; warnings are reported but the file is kept.
func LoadDir(dir string) (Library, []Problem, error) {
	paths, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return Library{}, nil, err
	}
	sort.Strings(paths)
	var lib Library
	var all []Problem
	cardOwner := map[string]string{}
	for _, p := range paths {
		name := filepath.Base(p)
		raw, err := os.ReadFile(p)
		if err != nil {
			return Library{}, nil, err
		}
		var f File
		dec := json.NewDecoder(strings.NewReader(string(raw)))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&f); err != nil {
			all = append(all, Problem{File: name, Message: "invalid JSON: " + err.Error()})
			continue
		}
		ps := ValidateFile(name, f)
		for _, c := range f.Cards {
			if other, ok := cardOwner[c.ID]; ok && other != name {
				ps = append(ps, Problem{File: name, Card: c.ID, Field: "id", Message: "also used in " + other})
			}
		}
		all = append(all, ps...)
		if hasError(ps) {
			continue
		}
		for _, c := range f.Cards {
			cardOwner[c.ID] = name
		}
		lib.Files = append(lib.Files, f)
	}
	return lib, all, nil
}

func hasError(ps []Problem) bool {
	for _, p := range ps {
		if !p.Warning {
			return true
		}
	}
	return false
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
