package rebornai

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"sync"
)

// The card studio makes media for cards members write: an image, the card
// read aloud, or an illustrated video (illustrations shown in turn over the
// narration). Prices are in docs/AI_UNITS.md.

// Kinds of card media charge. Images use the sketch, illustration and picture kinds.
const (
	KindAudio = "audio"
	KindVideo = "video"
)

// VideoScenes is how many illustrations an illustrated video has.
const VideoScenes = 4

// wordsPerAudioUnit is how many words of narration one unit covers. OpenAI's
// speech (the fallback when our own Kokoro voice is down) costs about $0.015 a
// minute, and a minute is about 150 words, so 50 words is about $0.005.
const wordsPerAudioUnit = 50

// AudioUnits is what reading text aloud costs: one unit per started 50 words.
func AudioUnits(text string) int {
	return max(1, (len(strings.Fields(text))+wordsPerAudioUnit-1)/wordsPerAudioUnit)
}

// VideoUnits is what an illustrated video of text costs: a unit to plan the
// scenes, an illustration per scene, and the narration.
func VideoUnits(text string) int {
	return 1 + VideoScenes*UnitsFor(KindIllustration) + AudioUnits(text)
}

// MediaRate describes a card media price for display.
type MediaRate struct {
	Kind  string `json:"kind"`
	Units int    `json:"units"`
	Per   string `json:"per"`
}

// MediaRates are the card studio's prices, in display order. A one-minute
// card (about 150 words) is used for the audio and video examples.
func MediaRates() []MediaRate {
	minute := strings.Repeat("word ", 150)
	return []MediaRate{
		{KindSketch, UnitsFor(KindSketch), "sketch"},
		{KindIllustration, UnitsFor(KindIllustration), "illustration"},
		{KindPicture, UnitsFor(KindPicture), "photo-like picture"},
		{KindAudio, AudioUnits(minute), "minute of audio (1 unit per 50 words)"},
		{KindVideo, VideoUnits(minute), fmt.Sprintf("illustrated video of a one-minute card (%d illustrations and narration)", VideoScenes)},
	}
}

// CardImage makes a picture for a card in one of the image styles and saves
// it. The same request reuses the saved picture.
func (a *Assistant) CardImage(ctx context.Context, userID, style, prompt, shape string) (url string, width, height int, err error) {
	prefix, ok := styles[style]
	if !ok {
		return "", 0, 0, fmt.Errorf("unknown style %q", style)
	}
	size, ok := shapes[shape]
	if !ok {
		size = shapes["square"]
	}
	m := a.Models.Picture
	switch style {
	case KindSketch:
		m = a.Models.Sketch
	case KindIllustration:
		m = a.Models.Illustrate
	}
	req := ImageRequest{Model: m.Model, Prompt: prefix + truncate(strings.TrimSpace(prompt), 3000), Size: fmt.Sprintf("%dx%d", size[0], size[1]),
		Quality: m.Quality, OutputFormat: "webp", Compression: 80, User: safetyID(userID)}
	url, err = a.saveImage(ctx, req)
	return url, size[0], size[1], err
}

// CardPrompt is the image prompt for a card when the member doesn't write one.
func CardPrompt(title, body string) string {
	return "An image that captures this idea, with no words in it. " + title + ". " + truncate(body, 800)
}

const scenesInstructions = `You plan short illustrated videos for Reborn, an app of one-minute idea cards. You are given a card. Write %d image prompts, one per scene, that follow the card from start to end; the narration is the card read aloud, and each scene is on screen for an equal share of it. Each prompt describes one concrete, warm, uplifting scene in a sentence or two: people, places and objects, never words, letters, logos or real, named people. Keep the same characters and setting from scene to scene. Reply with only a JSON array of %d strings.`

var jsonArrayRe = regexp.MustCompile(`(?s)\[.*\]`)

// ScenePrompts plans the illustrations of a video. When planning fails it
// falls back to prompts made from the card's own sentences.
func (a *Assistant) ScenePrompts(ctx context.Context, userID, title, body string) []string {
	rr := ResponseRequest{Model: a.Models.Chat, Instructions: fmt.Sprintf(scenesInstructions, VideoScenes, VideoScenes),
		Input: []json.RawMessage{message("user", title+"\n\n"+truncate(body, 4000))}, Store: false, MaxOutputTokens: 2000, User: safetyID(userID)}
	if a.Models.Effort != "" {
		rr.Reasoning = &Reasoning{Effort: a.Models.Effort}
	}
	if resp, err := a.AI.Respond(ctx, rr); err == nil {
		var sb strings.Builder
		for _, raw := range resp.Output {
			var it OutputItem
			if json.Unmarshal(raw, &it) == nil && it.Type == "message" {
				for _, c := range it.Content {
					sb.WriteString(c.Text)
				}
			}
		}
		var prompts []string
		if m := jsonArrayRe.FindString(sb.String()); m != "" && json.Unmarshal([]byte(m), &prompts) == nil && len(prompts) >= VideoScenes {
			ok := true
			for _, p := range prompts[:VideoScenes] {
				ok = ok && strings.TrimSpace(p) != ""
			}
			if ok {
				return prompts[:VideoScenes]
			}
		}
	}
	return fallbackScenes(title, body)
}

var sentenceRe = regexp.MustCompile(`[^.!?]+[.!?]*`)

// fallbackScenes splits the card into VideoScenes runs of sentences, one per scene.
func fallbackScenes(title, body string) []string {
	sentences := sentenceRe.FindAllString(body, -1)
	out := make([]string, VideoScenes)
	for i := range out {
		lo, hi := i*len(sentences)/VideoScenes, (i+1)*len(sentences)/VideoScenes
		part := strings.TrimSpace(strings.Join(sentences[lo:hi], " "))
		if part == "" {
			part = title
		}
		out[i] = fmt.Sprintf("Scene %d of %d illustrating the idea \"%s\": %s", i+1, VideoScenes, title, truncate(part, 600))
	}
	return out
}

// VideoImage is one scene picture.
type VideoImage struct {
	URL           string
	Width, Height int
}

// VideoImages makes the portrait illustrations of a video, all at once.
func (a *Assistant) VideoImages(ctx context.Context, userID string, prompts []string) ([]VideoImage, error) {
	out := make([]VideoImage, len(prompts))
	errs := make([]error, len(prompts))
	var wg sync.WaitGroup
	for i, p := range prompts {
		wg.Add(1)
		go func() {
			defer wg.Done()
			url, w, h, err := a.CardImage(ctx, userID, KindIllustration, p, "portrait")
			out[i], errs[i] = VideoImage{URL: url, Width: w, Height: h}, err
		}()
	}
	wg.Wait()
	for _, err := range errs {
		if err != nil {
			return nil, err
		}
	}
	return out, nil
}

// SpeakAs reads text aloud in one of the approved Kokoro voices and saves it
// under key; OpenAI reads it when Kokoro is down. Saved audio is reused.
func (a *Assistant) SpeakAs(ctx context.Context, key, text, voice string) (string, error) {
	saved := *a
	if voice != "" {
		saved.KokoroVoice = voice
	}
	url, _, err := saved.Speak(ctx, key, text)
	return url, err
}
