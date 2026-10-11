package rebornai

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/embed"
	"github.com/appsotechltd/reborn/backend/internal/objstore"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Library is the part of the store Reborn AI reads and writes.
type Library interface {
	Search(ctx context.Context, p store.SearchParams) ([]store.Card, error)
	SourceCards(ctx context.Context, id string) (content.Source, []store.Card, error)
	Stashes(ctx context.Context, userID string) ([]store.Stash, error)
	CreateStash(ctx context.Context, userID, name, desc string) (store.Stash, error)
	AddToStash(ctx context.Context, userID, stashID, cardID string, now time.Time) error
}

// Models picks the OpenAI model for each job.
type Models struct {
	Chat       string // text replies with function calling
	Effort     string // reasoning effort for Chat; "" for a non-reasoning model
	Transcribe string
	Speech     string
	Voice      string // text-to-speech voice
	Sketch     ImageModel
	Illustrate ImageModel
	Picture    ImageModel
}

// ImageModel is an image model at a quality.
type ImageModel struct {
	Model   string
	Quality string
}

// DefaultModels are the models the pricing in docs/AI_UNITS.md assumes.
var DefaultModels = Models{
	Chat:       "gpt-5.4-mini",
	Effort:     "low",
	Transcribe: "gpt-4o-mini-transcribe",
	Speech:     "gpt-4o-mini-tts",
	Voice:      "marin",
	Sketch:     ImageModel{"gpt-image-1-mini", "low"},
	Illustrate: ImageModel{"gpt-image-1-mini", "medium"},
	Picture:    ImageModel{"gpt-image-2", "medium"},
}

// Assistant is Reborn AI.
type Assistant struct {
	AI *OpenAI
	// Kokoro, when set, reads replies aloud for free with Reborn's own Kokoro
	// speech service (services/kokoro), which speaks OpenAI's speech API. OpenAI
	// stays the fallback when it is down.
	Kokoro      *OpenAI
	KokoroVoice string // an approved Kokoro voice; default af_heart
	Lib         Library
	Embedder    embed.Embedder // optional; keyword search works without it
	Media       objstore.Store // where pictures and speech are saved
	Models      Models
	Now         func() time.Time
}

// Turn is one earlier message in a chat.
type Turn struct {
	Role    string // user or assistant
	Content string
}

// Request is one message to answer.
type Request struct {
	UserID  string
	History []Turn // earlier turns, oldest first
	Message string
	Voice   bool // the member spoke; the reply will be read aloud
	// Extras is how many units the member can spend on charts and pictures in
	// this reply, after the reply itself.
	Extras int
}

// Charge is one paid action in a reply.
type Charge struct {
	Kind  string `json:"kind"`
	Units int    `json:"units"`
}

// Attachment is a picture or chart in a reply.
type Attachment struct {
	Type   string `json:"type"`            // image or chart
	Style  string `json:"style,omitempty"` // sketch, illustration or picture
	URL    string `json:"url,omitempty"`
	Alt    string `json:"alt,omitempty"`
	Width  int    `json:"width,omitempty"`
	Height int    `json:"height,omitempty"`
	Chart  *Chart `json:"chart,omitempty"`
}

// Chart is data the apps draw as a bar, line or pie chart.
type Chart struct {
	Kind   string   `json:"kind"`
	Title  string   `json:"title"`
	Unit   string   `json:"unit,omitempty"`
	Labels []string `json:"labels"`
	Series []Series `json:"series"`
}

// Series is one named row of chart values, one per label.
type Series struct {
	Name   string    `json:"name"`
	Values []float64 `json:"values"`
}

// Reply is Reborn AI's answer.
type Reply struct {
	Text        string
	Citations   []store.Card
	Attachments []Attachment
	Charges     []Charge // extras only; the reply itself is charged by the caller
}

const (
	maxRounds         = 5
	maxPicturesPerMsg = 2
	maxChartsPerMsg   = 3
)

const instructions = `You are Reborn AI, the premium assistant inside Reborn. Reborn turns the best ideas from books, textbooks, guides and talks into short, practical idea cards about work, mind, health, money, relationships, faith, parenting, learning and personal growth.

Help the member think, learn and act on ideas. Ground your answers in the Reborn library whenever it has something relevant: library results arrive as cards, each headed with its id in square brackets like [meditations-marcus-aurelius--01]. Search again with search_library, or read a whole source with get_source, when the cards you have miss. Cite every card you use by putting its id in square brackets right after the sentence that uses it. Only cite ids that appeared in library results in this chat. When the library has nothing on a question, you may help from general knowledge, but say that it isn't from the library, and keep to the kinds of topics Reborn covers.

You can act for the member: list_stashes shows their saved collections (stashes) and save_to_stash saves a card to one (or to a new one). Only save when they ask.

You can make visuals, and each one costs the member AI units, so only make one when they ask for it or it clearly helps:
- make_chart draws a bar, line or pie chart from numbers (1 unit). Use it for graphs and charts. Never invent statistics; chart only numbers the member gave you, numbers from the cards, or simple illustrative plans you label as examples.
- make_image makes a sketch (2 units), an illustration (4 units) or a photo-like picture (12 units). Pick the cheapest style that does the job; use picture only when they want something photo-like. Never make pictures of real people, logos, or anything sexual, violent or hateful.
If a tool says the member is out of units, tell them they can top up in Reborn AI's settings, and answer in words instead.

Write in your own words, warmly and briefly: a few short paragraphs or a short list, in plain text (the app shows no markdown, so no **bold**, # headings or tables; start list lines with "- "), ending with one concrete next step when it fits. For health and mental-health questions give general, evidence-based information, say it is not medical advice, and suggest a qualified professional for anything personal, urgent or persistent. If someone describes a crisis or risk of harm, encourage them to contact local emergency services or a crisis line right away.`

const voiceNote = `

The member is talking to you by voice, and your reply will be read aloud. Keep it under 120 words, in plain spoken sentences: no lists, headings, markdown or emoji. Still cite cards in square brackets; they are removed before speaking.`

var (
	mdEmphasis = regexp.MustCompile(`\*\*([^*\n]+)\*\*|__([^_\n]+)__`)
	mdHeading  = regexp.MustCompile(`(?m)^#{1,6}[ \t]+`)
	mdBullet   = regexp.MustCompile(`(?m)^([ \t]*)\*[ \t]+`)
)

// PlainText removes the markdown the apps can't show (bold, headings, "*"
// bullets) that a model sometimes writes despite being asked not to.
func PlainText(s string) string {
	s = mdEmphasis.ReplaceAllString(s, "$1$2")
	s = mdHeading.ReplaceAllString(s, "")
	s = mdBullet.ReplaceAllString(s, "$1- ")
	return strings.TrimSpace(s)
}

// Chat answers one message.
func (a *Assistant) Chat(ctx context.Context, req Request) (Reply, error) {
	if strings.TrimSpace(req.Message) == "" {
		return Reply{}, errors.New("empty message")
	}
	t := &turn{a: a, req: req, seen: map[string]store.Card{}, extras: req.Extras}
	initial, err := t.search(ctx, req.Message, "")
	if err != nil {
		return Reply{}, err
	}

	input := make([]json.RawMessage, 0, len(req.History)+8)
	for _, h := range req.History {
		input = append(input, message(h.Role, h.Content))
	}
	input = append(input, message("user", fmt.Sprintf("%s\n\n<library_results query=%q>\n%s</library_results>", req.Message, req.Message, render(initial))))

	instr := instructions
	if req.Voice {
		instr += voiceNote
	}
	var text string
	for round := 0; ; round++ {
		rr := ResponseRequest{
			Model: a.Models.Chat, Instructions: instr, Input: input, Tools: tools, Store: false,
			MaxOutputTokens: 4000, User: safetyID(req.UserID),
		}
		if a.Models.Effort != "" {
			rr.Reasoning = &Reasoning{Effort: a.Models.Effort}
			rr.Include = []string{"reasoning.encrypted_content"}
		}
		if round == maxRounds-1 {
			rr.Tools = nil // last round: answer with what it has
		}
		resp, err := a.AI.Respond(ctx, rr)
		if err != nil {
			return Reply{}, err
		}
		var calls []OutputItem
		var sb strings.Builder
		for _, raw := range resp.Output {
			var it OutputItem
			if err := json.Unmarshal(raw, &it); err != nil {
				return Reply{}, err
			}
			switch it.Type {
			case "function_call":
				calls = append(calls, it)
			case "message":
				for _, c := range it.Content {
					if c.Type == "output_text" {
						sb.WriteString(c.Text)
					}
				}
			}
			input = append(input, raw)
		}
		if len(calls) == 0 || round == maxRounds-1 {
			text = PlainText(sb.String())
			break
		}
		for _, c := range calls {
			out := t.call(ctx, c.Name, c.Arguments)
			item, _ := json.Marshal(map[string]string{"type": "function_call_output", "call_id": c.CallID, "output": out})
			input = append(input, item)
		}
	}
	if text == "" {
		text = "I couldn't put an answer together this time. Try asking in a different way."
	}
	return Reply{Text: text, Citations: t.cited(text), Attachments: t.attachments, Charges: t.charges}, nil
}

func message(role, text string) json.RawMessage {
	b, _ := json.Marshal(map[string]string{"role": role, "content": text})
	return b
}

// safetyID is a stable, non-identifying id OpenAI uses to spot abuse.
func safetyID(userID string) string {
	if userID == "" {
		return ""
	}
	sum := sha256.Sum256([]byte("reborn:" + userID))
	return hex.EncodeToString(sum[:16])
}

// turn is the state of one reply while tools run.
type turn struct {
	a           *Assistant
	req         Request
	mu          sync.Mutex
	seen        map[string]store.Card
	extras      int
	attachments []Attachment
	charges     []Charge
	pictures    int
	charts      int
}

func (t *turn) search(ctx context.Context, q, topic string) ([]store.Card, error) {
	p := store.SearchParams{Query: q, Topic: topic, Limit: 8}
	if t.a.Embedder != nil {
		if vecs, err := t.a.Embedder.Embed(ctx, []string{q}, "query"); err == nil && len(vecs) == 1 {
			p.QueryVector = vecs[0]
		}
	}
	cards, err := t.a.Lib.Search(ctx, p)
	if err != nil {
		return nil, err
	}
	t.mu.Lock()
	for _, c := range cards {
		t.seen[c.ID] = c
	}
	t.mu.Unlock()
	return cards, nil
}

// spend takes units from this reply's budget, or reports that there aren't enough.
func (t *turn) spend(kind string, units int) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if units > t.extras {
		return false
	}
	t.extras -= units
	t.charges = append(t.charges, Charge{Kind: kind, Units: units})
	return true
}

func (t *turn) refund(kind string, units int) {
	t.mu.Lock()
	defer t.mu.Unlock()
	for i := len(t.charges) - 1; i >= 0; i-- {
		if t.charges[i].Kind == kind && t.charges[i].Units == units {
			t.charges = append(t.charges[:i], t.charges[i+1:]...)
			t.extras += units
			return
		}
	}
}

const outOfUnits = "The member doesn't have enough AI units left for this. Don't retry; tell them they can top up, and answer in words."

// call runs one tool and returns its result for the model.
func (t *turn) call(ctx context.Context, name, args string) string {
	out, err := t.run(ctx, name, args)
	if err != nil {
		if ctx.Err() != nil {
			return "Cancelled."
		}
		slog.Warn("reborn ai tool", "tool", name, "err", err)
		return "That didn't work: " + err.Error()
	}
	return out
}

func (t *turn) run(ctx context.Context, name, args string) (string, error) {
	switch name {
	case "search_library":
		var in struct {
			Query string  `json:"query"`
			Topic *string `json:"topic"`
		}
		if err := json.Unmarshal([]byte(args), &in); err != nil {
			return "", err
		}
		topic := ""
		if in.Topic != nil {
			topic = *in.Topic
		}
		if topic != "" && !content.IsTopic(topic) {
			return "Unknown topic. Use one of: " + topicList(), nil
		}
		cards, err := t.search(ctx, in.Query, topic)
		if err != nil {
			return "", err
		}
		if len(cards) == 0 {
			return "No cards matched. Try other words or a broader query.", nil
		}
		return render(cards), nil

	case "get_source":
		var in struct {
			SourceID string `json:"source_id"`
		}
		if err := json.Unmarshal([]byte(args), &in); err != nil {
			return "", err
		}
		src, cards, err := t.a.Lib.SourceCards(ctx, in.SourceID)
		if errors.Is(err, store.ErrNotFound) {
			return "No source with that id.", nil
		}
		if err != nil {
			return "", err
		}
		t.mu.Lock()
		for _, c := range cards {
			t.seen[c.ID] = c
		}
		t.mu.Unlock()
		return fmt.Sprintf("Source: %s by %s (%s)\n\n%s", src.Title, strings.Join(src.Authors, ", "), src.Attribution, render(cards)), nil

	case "list_stashes":
		stashes, err := t.a.Lib.Stashes(ctx, t.req.UserID)
		if err != nil {
			return "", err
		}
		if len(stashes) == 0 {
			return "The member has no stashes yet.", nil
		}
		var sb strings.Builder
		for _, s := range stashes {
			fmt.Fprintf(&sb, "- %s (id %s, %d cards)\n", s.Name, s.ID, s.CardCount)
		}
		return sb.String(), nil

	case "save_to_stash":
		var in struct {
			CardID       string  `json:"card_id"`
			StashID      *string `json:"stash_id"`
			NewStashName *string `json:"new_stash_name"`
		}
		if err := json.Unmarshal([]byte(args), &in); err != nil {
			return "", err
		}
		var stashID, stashName string
		switch {
		case in.StashID != nil && *in.StashID != "":
			stashID = *in.StashID
		case in.NewStashName != nil && strings.TrimSpace(*in.NewStashName) != "":
			s, err := t.a.Lib.CreateStash(ctx, t.req.UserID, truncate(strings.TrimSpace(*in.NewStashName), 80), "")
			if err != nil {
				return "", err
			}
			stashID, stashName = s.ID, s.Name
		default:
			return "Give a stash_id from list_stashes, or a new_stash_name.", nil
		}
		err := t.a.Lib.AddToStash(ctx, t.req.UserID, stashID, in.CardID, t.a.now())
		if errors.Is(err, store.ErrNotFound) {
			return "That stash or card doesn't exist.", nil
		}
		if err != nil {
			return "", err
		}
		if stashName != "" {
			return fmt.Sprintf("Saved %s to a new stash called %q.", in.CardID, stashName), nil
		}
		return "Saved " + in.CardID + ".", nil

	case "make_chart":
		var c Chart
		if err := json.Unmarshal([]byte(args), &c); err != nil {
			return "", err
		}
		if err := c.validate(); err != nil {
			return "Chart not drawn: " + err.Error(), nil
		}
		if t.charts >= maxChartsPerMsg {
			return "That's enough charts for one reply.", nil
		}
		if !t.spend(KindChart, UnitsFor(KindChart)) {
			return outOfUnits, nil
		}
		t.mu.Lock()
		t.charts++
		t.attachments = append(t.attachments, Attachment{Type: "chart", Chart: &c, Alt: c.Title})
		t.mu.Unlock()
		return "Chart drawn below your reply. Refer to it, don't repeat its numbers.", nil

	case "make_image":
		var in struct {
			Style  string `json:"style"`
			Prompt string `json:"prompt"`
			Shape  string `json:"shape"`
			Alt    string `json:"alt"`
		}
		if err := json.Unmarshal([]byte(args), &in); err != nil {
			return "", err
		}
		return t.makeImage(ctx, in.Style, in.Prompt, in.Shape, in.Alt)
	}
	return "Unknown tool.", nil
}

var styles = map[string]string{
	KindSketch:       "A simple hand-drawn pencil sketch, dark lines on plain white paper, minimal shading, with no words, letters or numbers anywhere: ",
	KindIllustration: "A warm, friendly flat illustration with soft amber and deep brown tones, clean shapes, with no words, letters or numbers anywhere: ",
	KindPicture:      "A natural, photo-realistic image with soft warm light: ",
}

var shapes = map[string][2]int{"square": {1024, 1024}, "portrait": {1024, 1536}, "landscape": {1536, 1024}}

func (t *turn) makeImage(ctx context.Context, style, prompt, shape, alt string) (string, error) {
	prefix, ok := styles[style]
	if !ok {
		return "Style must be sketch, illustration or picture.", nil
	}
	size, ok := shapes[shape]
	if !ok {
		size = shapes["square"]
	}
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		return "Describe the image in the prompt.", nil
	}
	if t.pictures >= maxPicturesPerMsg {
		return "That's enough images for one reply.", nil
	}
	units := UnitsFor(style)
	if !t.spend(style, units) {
		return outOfUnits, nil
	}
	m := t.a.Models.Picture
	switch style {
	case KindSketch:
		m = t.a.Models.Sketch
	case KindIllustration:
		m = t.a.Models.Illustrate
	}
	req := ImageRequest{Model: m.Model, Prompt: prefix + truncate(prompt, 3000), Size: fmt.Sprintf("%dx%d", size[0], size[1]),
		Quality: m.Quality, OutputFormat: "webp", Compression: 80, User: safetyID(t.req.UserID)}
	url, err := t.a.saveImage(ctx, req)
	if IsModerationBlock(err) {
		t.refund(style, units)
		return "OpenAI declined to make that image. Tell the member it can't be made, without guessing why.", nil
	}
	if err != nil {
		t.refund(style, units)
		return "", err
	}
	if alt == "" {
		alt = truncate(prompt, 200)
	}
	t.mu.Lock()
	t.pictures++
	t.attachments = append(t.attachments, Attachment{Type: "image", Style: style, URL: url, Alt: alt, Width: size[0], Height: size[1]})
	t.mu.Unlock()
	return fmt.Sprintf("The %s is shown below your reply. Mention it briefly; don't describe it at length.", style), nil
}

// saveImage generates an image once and keeps it: the same request reuses the saved file.
func (a *Assistant) saveImage(ctx context.Context, req ImageRequest) (string, error) {
	sum := sha256.Sum256([]byte(req.Model + "\n" + req.Quality + "\n" + req.Size + "\n" + req.Prompt))
	key := "ai/images/" + hex.EncodeToString(sum[:12]) + ".webp"
	if ok, _, err := a.Media.Stat(ctx, key); err == nil && ok {
		return a.Media.URL(key), nil
	}
	img, err := a.AI.GenerateImage(ctx, req)
	if err != nil {
		return "", err
	}
	if err := a.Media.Put(ctx, key, "image/webp", bytes.NewReader(img), int64(len(img))); err != nil {
		return "", err
	}
	return a.Media.URL(key), nil
}

// Transcribe turns a voice message into text.
func (a *Assistant) Transcribe(ctx context.Context, filename string, audio []byte) (string, error) {
	text, err := a.AI.Transcribe(ctx, a.Models.Transcribe, filename, audio)
	return strings.TrimSpace(text), err
}

// Speak reads a reply aloud and saves the audio under key, so hearing it again is free.
// It returns the audio's URL and whether it was newly made.
func (a *Assistant) Speak(ctx context.Context, key, text string) (url string, made bool, err error) {
	if ok, _, err := a.Media.Stat(ctx, key); err == nil && ok {
		return a.Media.URL(key), false, nil
	}
	text = truncate(text, 4000)
	var audio []byte
	if a.Kokoro != nil {
		voice := a.KokoroVoice
		if voice == "" {
			voice = "af_heart"
		}
		audio, err = a.Kokoro.Speak(ctx, SpeechRequest{Model: "kokoro", Voice: voice, Input: text})
		if err != nil {
			slog.Warn("kokoro speech failed; using OpenAI", "err", err)
		}
	}
	if a.Kokoro == nil || err != nil {
		audio, err = a.AI.Speak(ctx, SpeechRequest{Model: a.Models.Speech, Voice: a.Models.Voice, Input: text,
			Instructions: "Speak warmly and calmly, like a thoughtful friend, at an easy pace."})
		if err != nil {
			return "", false, err
		}
	}
	if err := a.Media.Put(ctx, key, "audio/mpeg", bytes.NewReader(audio), int64(len(audio))); err != nil {
		return "", false, err
	}
	return a.Media.URL(key), true, nil
}

func (a *Assistant) now() time.Time {
	if a.Now != nil {
		return a.Now()
	}
	return time.Now()
}

func (c *Chart) validate() error {
	switch c.Kind {
	case "bar", "line", "pie":
	default:
		return errors.New("kind must be bar, line or pie")
	}
	if len(c.Labels) == 0 || len(c.Labels) > 24 {
		return errors.New("give 1 to 24 labels")
	}
	if len(c.Series) == 0 || len(c.Series) > 4 || (c.Kind == "pie" && len(c.Series) != 1) {
		return errors.New("give 1 to 4 series (a pie chart takes exactly 1)")
	}
	for _, s := range c.Series {
		if len(s.Values) != len(c.Labels) {
			return errors.New("each series needs one value per label")
		}
		for _, v := range s.Values {
			if c.Kind == "pie" && v < 0 {
				return errors.New("pie values can't be negative")
			}
		}
	}
	c.Title = truncate(c.Title, 120)
	return nil
}

func (t *turn) cited(text string) []store.Card {
	t.mu.Lock()
	defer t.mu.Unlock()
	out := []store.Card{}
	done := map[string]bool{}
	for _, m := range citeRe.FindAllStringSubmatch(text, -1) {
		if c, ok := t.seen[m[1]]; ok && !done[m[1]] {
			out = append(out, c)
			done[m[1]] = true
		}
	}
	return out
}

var citeRe = regexp.MustCompile(`\[([a-z0-9]+(?:-[a-z0-9]+)*--[0-9]{2,3})\]`)

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

func topicList() string {
	slugs := make([]string, len(content.Topics))
	for i, t := range content.Topics {
		slugs[i] = t.Slug
	}
	return strings.Join(slugs, ", ")
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	for n > 0 && (s[n]&0xC0) == 0x80 { // don't split a UTF-8 character
		n--
	}
	return s[:n]
}

var tools = []Tool{
	{Type: "function", Name: "search_library", Strict: true,
		Description: "Search the Reborn card library. Returns up to 8 idea cards, each headed with its [card-id]. Use short keyword queries; call again with different words if results miss.",
		Parameters: json.RawMessage(`{"type":"object","properties":{
			"query":{"type":"string","description":"Keywords to search for"},
			"topic":{"type":["string","null"],"description":"Optional topic slug to restrict results, or null"}},
			"required":["query","topic"],"additionalProperties":false}`)},
	{Type: "function", Name: "get_source", Strict: true,
		Description: "Read every card from one source. The source id is the part of a card id before the double dash.",
		Parameters: json.RawMessage(`{"type":"object","properties":{"source_id":{"type":"string"}},
			"required":["source_id"],"additionalProperties":false}`)},
	{Type: "function", Name: "list_stashes", Strict: true,
		Description: "List the member's stashes (saved collections of cards) with their ids.",
		Parameters:  json.RawMessage(`{"type":"object","properties":{},"required":[],"additionalProperties":false}`)},
	{Type: "function", Name: "save_to_stash", Strict: true,
		Description: "Save a card to one of the member's stashes, or to a new stash. Only when the member asks.",
		Parameters: json.RawMessage(`{"type":"object","properties":{
			"card_id":{"type":"string"},
			"stash_id":{"type":["string","null"],"description":"An id from list_stashes, or null to make a new stash"},
			"new_stash_name":{"type":["string","null"],"description":"Name for a new stash when stash_id is null"}},
			"required":["card_id","stash_id","new_stash_name"],"additionalProperties":false}`)},
	{Type: "function", Name: "make_chart", Strict: true,
		Description: "Draw a bar, line or pie chart under the reply. Costs the member 1 AI unit.",
		Parameters: json.RawMessage(`{"type":"object","properties":{
			"kind":{"type":"string","enum":["bar","line","pie"]},
			"title":{"type":"string"},
			"unit":{"type":["string","null"],"description":"Unit of the values, like minutes or %, or null"},
			"labels":{"type":"array","items":{"type":"string"},"description":"Category or x-axis labels, at most 24"},
			"series":{"type":"array","description":"1 to 4 series; a pie takes 1","items":{"type":"object","properties":{
				"name":{"type":"string"},
				"values":{"type":"array","items":{"type":"number"},"description":"One value per label"}},
				"required":["name","values"],"additionalProperties":false}}},
			"required":["kind","title","unit","labels","series"],"additionalProperties":false}`)},
	{Type: "function", Name: "make_image", Strict: true,
		Description: "Make an image shown under the reply. sketch costs 2 AI units, illustration 4, picture (photo-like) 12. Pick the cheapest style that does the job. Images can't hold readable writing, so describe pictures only and put any words (steps, labels, titles) in your reply instead.",
		Parameters: json.RawMessage(`{"type":"object","properties":{
			"style":{"type":"string","enum":["sketch","illustration","picture"]},
			"prompt":{"type":"string","description":"What to draw, in detail"},
			"shape":{"type":"string","enum":["square","portrait","landscape"]},
			"alt":{"type":"string","description":"One-sentence description for screen readers"}},
			"required":["style","prompt","shape","alt"],"additionalProperties":false}`)},
}
