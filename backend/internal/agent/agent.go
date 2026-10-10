// Package agent answers questions with Claude, grounded in the card library.
//
// It is retrieval-augmented, not fine-tuned: every question first searches the
// library, Claude can search again with a tool, and the answer must cite the
// cards it used as [card-id]. Only cards the agent actually retrieved can be
// cited, so a citation always points at a real card.
package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"sync"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
	"github.com/anthropics/anthropic-sdk-go/toolrunner"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/embed"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Library is the part of the store the agent reads.
type Library interface {
	Search(ctx context.Context, p store.SearchParams) ([]store.Card, error)
	SourceCards(ctx context.Context, id string) (content.Source, []store.Card, error)
}

// Message is one chat turn.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// Reply is the agent's answer and the cards it cited, in order of first mention.
type Reply struct {
	Text      string
	Citations []store.Card
}

// ErrBadConversation means the history is empty, too long or malformed.
var ErrBadConversation = errors.New("conversation must alternate user/assistant turns and end with a user message")

// Agent answers questions about the library.
type Agent struct {
	client   anthropic.Client
	model    string
	lib      Library
	embedder embed.Embedder
}

// New returns an Agent. Extra client options (for example a base URL in tests) are passed through.
func New(apiKey, model string, lib Library, e embed.Embedder, opts ...option.RequestOption) *Agent {
	opts = append([]option.RequestOption{option.WithAPIKey(apiKey)}, opts...)
	return &Agent{client: anthropic.NewClient(opts...), model: model, lib: lib, embedder: e}
}

const systemPrompt = `You are Reborn's guide. Reborn turns the best ideas from books, textbooks, guides and talks into short, practical idea cards about work, mind, health, money and relationships.

Answer the user's question using only the idea cards in the Reborn library. Results from the library arrive as cards, each headed with its id in square brackets, like [meditations-marcus-aurelius--01]. If the cards you have do not cover the question, call search_library with a better query, or get_source to read every card from one source. When the library still has nothing relevant, say so plainly and suggest a nearby topic it does cover; do not fill the gap from general knowledge.

Cite every idea you use by putting its card id in square brackets right after the sentence that uses it, for example: "Naming a problem before the day starts takes the sting out of it [meditations-marcus-aurelius--01]." Only cite ids that appeared in library results in this conversation.

Write in your own words, warmly and briefly: a few short paragraphs or a short list, then one concrete next step the user could take, drawn from a card's "Apply it" line. Quote a card's quote only when it adds something, and keep quotes short.

For health and mental-health questions, keep to general, evidence-based information from the cards, say it is not medical advice, and suggest seeing a qualified professional for anything personal, urgent or persistent. If someone describes a crisis or risk of harm, encourage them to contact local emergency services or a crisis line right away.`

// Chat answers the last user message given the whole conversation.
func (a *Agent) Chat(ctx context.Context, history []Message) (Reply, error) {
	if err := validate(history); err != nil {
		return Reply{}, err
	}
	seen := newCardSet()
	question := history[len(history)-1].Content
	initial, err := a.search(ctx, question, "", 8)
	if err != nil {
		return Reply{}, err
	}
	seen.add(initial...)

	msgs := make([]anthropic.BetaMessageParam, 0, len(history))
	for i, m := range history {
		text := m.Content
		if i == len(history)-1 {
			text = fmt.Sprintf("%s\n\n<library_results query=%q>\n%s</library_results>", m.Content, question, render(initial))
		}
		block := anthropic.NewBetaTextBlock(text)
		if m.Role == "user" {
			msgs = append(msgs, anthropic.NewBetaUserMessage(block))
		} else {
			msgs = append(msgs, anthropic.BetaMessageParam{Role: anthropic.BetaMessageParamRoleAssistant, Content: []anthropic.BetaContentBlockParamUnion{block}})
		}
	}

	searchTool, err := toolrunner.NewBetaToolFromJSONSchema("search_library",
		"Search the Reborn card library. Returns up to 8 idea cards, each headed with its [card-id]. Use short keyword queries; call again with different words if results miss.",
		func(ctx context.Context, in searchInput) (anthropic.BetaToolResultBlockParamContentUnion, error) {
			if in.Topic != "" && !content.IsTopic(in.Topic) {
				return textResult("Unknown topic. Use one of: " + topicList()), nil
			}
			cards, err := a.search(ctx, in.Query, in.Topic, 8)
			if err != nil {
				return anthropic.BetaToolResultBlockParamContentUnion{}, err
			}
			seen.add(cards...)
			if len(cards) == 0 {
				return textResult("No cards matched. Try other words or a broader query."), nil
			}
			return textResult(render(cards)), nil
		})
	if err != nil {
		return Reply{}, err
	}
	sourceTool, err := toolrunner.NewBetaToolFromJSONSchema("get_source",
		"Read every card from one source (the source id is the part of a card id before the double dash).",
		func(ctx context.Context, in sourceInput) (anthropic.BetaToolResultBlockParamContentUnion, error) {
			src, cards, err := a.lib.SourceCards(ctx, in.SourceID)
			if errors.Is(err, store.ErrNotFound) {
				return textResult("No source with that id."), nil
			}
			if err != nil {
				return anthropic.BetaToolResultBlockParamContentUnion{}, err
			}
			seen.add(cards...)
			return textResult(fmt.Sprintf("Source: %s by %s (%s)\n\n%s", src.Title, strings.Join(src.Authors, ", "), src.Attribution, render(cards))), nil
		})
	if err != nil {
		return Reply{}, err
	}

	runner := a.client.Beta.Messages.NewToolRunner([]anthropic.BetaTool{searchTool, sourceTool}, anthropic.BetaToolRunnerParams{
		BetaMessageNewParams: anthropic.BetaMessageNewParams{
			Model:     a.model,
			MaxTokens: 16000,
			System:    []anthropic.BetaTextBlockParam{{Text: systemPrompt, CacheControl: anthropic.NewBetaCacheControlEphemeralParam()}},
			Messages:  msgs,
			OutputConfig: anthropic.BetaOutputConfigParam{
				Effort: anthropic.BetaOutputConfigEffortMedium,
			},
			// A safety classifier can decline a benign request; let the API
			// re-serve it on Anthropic's recommended fallback model.
			Fallbacks: anthropic.BetaFallbacksParamOfDefault(),
			Betas:     []anthropic.AnthropicBeta{anthropic.AnthropicBetaServerSideFallback2026_07_01},
		},
		MaxIterations: 6,
	})
	msg, err := runner.RunToCompletion(ctx)
	if err != nil {
		return Reply{}, err
	}
	if msg.StopReason == anthropic.BetaStopReasonRefusal {
		return Reply{Text: "I can't help with that one. Try asking about an idea from the library, like habits, focus, sleep or handling difficult people."}, nil
	}
	var sb strings.Builder
	for _, block := range msg.Content {
		if t, ok := block.AsAny().(anthropic.BetaTextBlock); ok {
			sb.WriteString(t.Text)
		}
	}
	text := strings.TrimSpace(sb.String())
	if text == "" {
		text = "I couldn't put an answer together from the library this time. Try asking in a different way."
	}
	return Reply{Text: text, Citations: seen.cited(text)}, nil
}

type searchInput struct {
	Query string `json:"query" jsonschema:"required,description=Keywords to search for"`
	Topic string `json:"topic,omitempty" jsonschema:"description=Optional topic slug to restrict results"`
}

type sourceInput struct {
	SourceID string `json:"source_id" jsonschema:"required,description=The source id"`
}

func (a *Agent) search(ctx context.Context, q, topic string, limit int) ([]store.Card, error) {
	p := store.SearchParams{Query: q, Topic: topic, Limit: limit}
	if a.embedder != nil {
		// Semantic search is a bonus; keyword search still works without it.
		if vecs, err := a.embedder.Embed(ctx, []string{q}, "query"); err == nil && len(vecs) == 1 {
			p.QueryVector = vecs[0]
		}
	}
	return a.lib.Search(ctx, p)
}

func validate(h []Message) error {
	if len(h) == 0 || len(h) > 40 {
		return ErrBadConversation
	}
	for i, m := range h {
		want := "user"
		if i%2 == 1 {
			want = "assistant"
		}
		if m.Role != want || strings.TrimSpace(m.Content) == "" || len(m.Content) > 8000 {
			return ErrBadConversation
		}
	}
	if h[len(h)-1].Role != "user" {
		return ErrBadConversation
	}
	return nil
}

func textResult(s string) anthropic.BetaToolResultBlockParamContentUnion {
	return anthropic.BetaToolResultBlockParamContentUnion{OfText: &anthropic.BetaTextBlockParam{Text: s}}
}

func topicList() string {
	slugs := make([]string, len(content.Topics))
	for i, t := range content.Topics {
		slugs[i] = t.Slug
	}
	return strings.Join(slugs, ", ")
}

// render formats cards for the model.
func render(cards []store.Card) string {
	if len(cards) == 0 {
		return "(no matching cards)\n"
	}
	var sb strings.Builder
	for _, c := range cards {
		fmt.Fprintf(&sb, "[%s] %s\nTopic: %s. %s\n%s\nApply it: %s\n", c.ID, c.Title, c.Topic, c.Credit, c.Body, c.ApplyIt)
		if c.Quote != nil {
			fmt.Fprintf(&sb, "Quote: %q\n", *c.Quote)
		}
		if c.Health {
			sb.WriteString("(Health card: general information, not medical advice.)\n")
		}
		sb.WriteString("\n")
	}
	return sb.String()
}

var citeRe = regexp.MustCompile(`\[([a-z0-9]+(?:-[a-z0-9]+)*--[0-9]{2,3})\]`)

// cardSet records every card the agent has retrieved. Tools may run
// concurrently, so it is guarded by a mutex.
type cardSet struct {
	mu   sync.Mutex
	byID map[string]store.Card
}

func newCardSet() *cardSet { return &cardSet{byID: map[string]store.Card{}} }

func (s *cardSet) add(cards ...store.Card) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, c := range cards {
		s.byID[c.ID] = c
	}
}

// cited returns the retrieved cards referenced in text, in order of first mention.
func (s *cardSet) cited(text string) []store.Card {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []store.Card{}
	done := map[string]bool{}
	for _, m := range citeRe.FindAllStringSubmatch(text, -1) {
		id := m[1]
		if c, ok := s.byID[id]; ok && !done[id] {
			out = append(out, c)
			done[id] = true
		}
	}
	return out
}

// MarshalJSON keeps Reply's wire shape in one place.
func (r Reply) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Reply     string       `json:"reply"`
		Citations []store.Card `json:"citations"`
	}{r.Text, r.Citations})
}
