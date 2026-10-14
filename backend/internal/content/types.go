// Package content defines the library file format described in content/SCHEMA.md
// and validates files against it.
package content

// File is one content/library/<source-id>.json file.
type File struct {
	Source Source `json:"source"`
	Cards  []Card `json:"cards"`
}

// Source is the book, article, guide or talk a set of cards comes from.
type Source struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Authors     []string `json:"authors"`
	Kind        string   `json:"kind"`
	URL         string   `json:"url"`
	Licence     string   `json:"licence"`
	LicenceURL  string   `json:"licence_url"`
	Attribution string   `json:"attribution"`
	Publisher   string   `json:"publisher,omitempty"`
	Year        *int     `json:"year,omitempty"`
	Language    string   `json:"language,omitempty"`
	Translator  string   `json:"translator,omitempty"`
	RetrievedAt string   `json:"retrieved_at"`
	Notes       string   `json:"notes,omitempty"`
}

// Card is one idea card.
type Card struct {
	ID       string   `json:"id"`
	Topic    string   `json:"topic"`
	Tags     []string `json:"tags,omitempty"`
	Title    string   `json:"title"`
	Body     string   `json:"body"`
	Quote    string   `json:"quote,omitempty"`
	ApplyIt  string   `json:"apply_it"`
	Locator  string   `json:"locator,omitempty"`
	Quiz     *Quiz    `json:"quiz,omitempty"`
	Health   bool     `json:"health,omitempty"`
	Language string   `json:"language,omitempty"`
}

// Quiz is a multiple-choice question used by review and quizzes.
type Quiz struct {
	Question    string   `json:"question"`
	Options     []string `json:"options"`
	Answer      int      `json:"answer"`
	Explanation string   `json:"explanation,omitempty"`
}

// Topic is one of the fixed top-level categories.
type Topic struct {
	Slug string `json:"slug"`
	Name string `json:"name"`
}

// Topics lists the categories in display order.
var Topics = []Topic{
	{"business", "Business"},
	{"psychology", "Psychology"},
	{"mental-strength", "Mental Strength & Resilience"},
	{"health", "Health & Wellness"},
	{"emotional-intelligence", "Emotional Intelligence"},
	{"personal-development", "Personal Development"},
	{"productivity", "Productivity & Career"},
	{"money", "Money"},
	{"relationships", "Relationships"},
	{"dating-marriage", "Dating & Marriage"},
	{"mindfulness", "Mindfulness & Philosophy"},
	{"faith-wisdom", "Faith & Wisdom"},
	{"leadership", "Leadership"},
	{"parenting", "Parenting & Family"},
	{"communication", "Communication & Influence"},
	{"creativity", "Creativity"},
	{"learning", "Learning & Thinking"},
	{"lives-history", "Lives & History"},
	{"entrepreneurship", "Entrepreneurship"},
	{"heartbreak-healing", "Heartbreak & Healing"},
	{"grief-loss", "Grief & Loss"},
	{"study-smarter", "Study Smarter"},
	{"skills-mastery", "Skills & Mastery"},
	{"etiquette", "Etiquette & Manners"},
	{"life-guides", "Life Guides"},
}

// Kinds lists the allowed source kinds.
var Kinds = []string{"book", "textbook", "article", "guide", "study", "talk", "podcast", "video"}

// Licences maps each allowed licence code to whether verbatim quotes are allowed.
var Licences = map[string]bool{
	"public-domain":        true,
	"us-gov-public-domain": true,
	"cc-by-4.0":            true,
	"cc-by-3.0":            true,
	"cc-by-sa-4.0":         true,
	"cc0-1.0":              true,
	"ogl-3.0":              true,
	"original-summary":     false,
}

// SupportTopics are about painful experiences; their cards carry SupportNote.
var SupportTopics = map[string]bool{"heartbreak-healing": true, "grief-loss": true}

// SupportNote is shown on every card in a support topic, in place of the health disclaimer.
const SupportNote = "If you're finding things hard, you don't have to go through it alone. Talk to someone you trust, or reach out to a counsellor, your doctor or a local support line."

// HealthDisclaimer is shown on every card flagged as health.
const HealthDisclaimer = "This is general information, not medical advice. Talk to a qualified health professional about your own situation."

// IsTopic reports whether slug is a known topic.
func IsTopic(slug string) bool {
	for _, t := range Topics {
		if t.Slug == slug {
			return true
		}
	}
	return false
}
