package content

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func validFile() File {
	return File{
		Source: Source{
			ID: "test-source", Title: "Test", Authors: []string{"A"}, Kind: "book",
			URL: "https://example.com", Licence: "public-domain", LicenceURL: "https://example.com/l",
			Attribution: "A, Test, public domain", RetrievedAt: "2026-10-10",
		},
		Cards: []Card{validCard("test-source--01"), validCard("test-source--02"), validCard("test-source--03")},
	}
}

func validCard(id string) Card {
	return Card{
		ID: id, Topic: "mindfulness", Title: "A title",
		Body:    strings.Repeat("word ", 30),
		ApplyIt: "Do a thing.",
	}
}

func messages(ps []Problem) string {
	var s []string
	for _, p := range ps {
		s = append(s, p.String())
	}
	return strings.Join(s, "\n")
}

func TestValidFile(t *testing.T) {
	if ps := ValidateFile("test-source.json", validFile()); len(ps) != 0 {
		t.Fatalf("unexpected problems:\n%s", messages(ps))
	}
}

func TestRules(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*File)
		want   string
	}{
		{"file name", func(f *File) { f.Source.ID = "other" }, "must equal the file name"},
		{"nc licence", func(f *File) { f.Source.Licence = "cc-by-nc-sa-4.0" }, "non-commercial"},
		{"unknown licence", func(f *File) { f.Source.Licence = "mit" }, "not an allowed licence"},
		{"quote on summary", func(f *File) { f.Source.Licence = "original-summary"; f.Cards[0].Quote = "x" }, "quotes are not allowed"},
		{"health flag", func(f *File) { f.Cards[0].Topic = "health" }, "must be true when topic is health"},
		{"bad topic", func(f *File) { f.Cards[0].Topic = "cooking" }, "not a known topic"},
		{"id prefix", func(f *File) { f.Cards[0].ID = "elsewhere--01" }, `must start with "test-source--"`},
		{"short body", func(f *File) { f.Cards[0].Body = "too short" }, "must be 25-160"},
		{"quiz answer", func(f *File) {
			f.Cards[0].Quiz = &Quiz{Question: "q", Options: []string{"a", "b"}, Answer: 2}
		}, "must index into options"},
		{"duplicate id", func(f *File) { f.Cards[1].ID = f.Cards[0].ID }, "duplicate card id"},
		{"date", func(f *File) { f.Source.RetrievedAt = "yesterday" }, "YYYY-MM-DD"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := validFile()
			tc.mutate(&f)
			got := messages(ValidateFile("test-source.json", f))
			if !strings.Contains(got, tc.want) {
				t.Fatalf("want a problem containing %q, got:\n%s", tc.want, got)
			}
		})
	}
}

func TestCardCountIsWarning(t *testing.T) {
	f := validFile()
	f.Cards = f.Cards[:1]
	ps := ValidateFile("test-source.json", f)
	if len(ps) != 1 || !ps[0].Warning {
		t.Fatalf("want one warning, got:\n%s", messages(ps))
	}
}

func TestLoadDir(t *testing.T) {
	lib, ps, err := LoadDir(filepath.Join("..", "..", "testdata", "library"))
	if err != nil {
		t.Fatal(err)
	}
	if hasError(ps) {
		t.Fatalf("fixtures invalid:\n%s", messages(ps))
	}
	if len(lib.Files) == 0 {
		t.Fatal("no fixtures loaded")
	}
}

func TestLoadDirSkipsBadFiles(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "broken.json"), []byte(`{"source": {}, "cards": [], "extra": 1}`), 0o644); err != nil {
		t.Fatal(err)
	}
	lib, ps, err := LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(lib.Files) != 0 || !hasError(ps) {
		t.Fatalf("broken file was accepted: %v", messages(ps))
	}
}

// TestRepoLibrary validates whatever is in content/library, so CI catches bad
// content as soon as it lands.
func TestRepoLibrary(t *testing.T) {
	_, ps, err := LoadDir(filepath.Join("..", "..", "..", "content", "library"))
	if err != nil {
		t.Fatal(err)
	}
	if hasError(ps) {
		t.Fatalf("content/library has errors:\n%s", messages(ps))
	}
}
