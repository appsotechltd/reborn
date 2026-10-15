package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/rebornai"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Member cards are idea cards people write themselves. They file them under
// their own categories, choose who sees each one (everyone, their followers,
// or only them), and premium members can make an image, an audio reading or an
// illustrated video for any of them with AI units.

const (
	maxCardTitle    = 120
	maxCardBody     = 1500
	maxCardApplyIt  = 400
	maxCategoryName = 40
	maxImagePrompt  = 1000
)

func (s *Server) limitReached(w http.ResponseWriter, r *http.Request, err error, what string) {
	if errors.Is(err, store.ErrLimit) {
		writeError(w, http.StatusConflict, "limit_reached", "you've reached the most "+what+" you can keep")
		return
	}
	s.fail(w, r, err, what)
}

// --- categories ---

func (s *Server) myCategories(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.MemberCategories(r.Context(), userID(r), true)
	if err != nil {
		s.fail(w, r, err, "categories")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"categories": list})
}

func categoryName(w http.ResponseWriter, r *http.Request) (string, bool) {
	var in struct {
		Name string `json:"name"`
	}
	if !decode(w, r, &in) {
		return "", false
	}
	in.Name = strings.Join(strings.Fields(in.Name), " ")
	if in.Name == "" || utf8.RuneCountInString(in.Name) > maxCategoryName {
		writeError(w, http.StatusBadRequest, "bad_request", "name must be 1 to 40 characters")
		return "", false
	}
	return in.Name, true
}

func (s *Server) createCategory(w http.ResponseWriter, r *http.Request) {
	name, ok := categoryName(w, r)
	if !ok {
		return
	}
	c, err := s.Store.CreateMemberCategory(r.Context(), userID(r), name)
	if err != nil {
		s.limitReached(w, r, err, "categories")
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) renameCategory(w http.ResponseWriter, r *http.Request) {
	name, ok := categoryName(w, r)
	if !ok {
		return
	}
	c, err := s.Store.RenameMemberCategory(r.Context(), userID(r), r.PathValue("id"), name)
	if err != nil {
		s.fail(w, r, err, "category")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) deleteCategory(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DeleteMemberCategory(r.Context(), userID(r), r.PathValue("id")); err != nil {
		s.fail(w, r, err, "category")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- cards ---

type memberCardBody struct {
	Title      *string `json:"title"`
	Body       *string `json:"body"`
	ApplyIt    *string `json:"apply_it"`
	Topic      *string `json:"topic"`
	CategoryID *string `json:"category_id"`
	Audience   *string `json:"audience"`
}

// input checks a card body. create requires the title, body and topic.
func (b memberCardBody) input(w http.ResponseWriter, create bool) (store.MemberCardInput, bool) {
	bad := func(msg string) (store.MemberCardInput, bool) {
		writeError(w, http.StatusBadRequest, "bad_request", msg)
		return store.MemberCardInput{}, false
	}
	trim := func(p *string) *string {
		if p == nil {
			return nil
		}
		t := strings.TrimSpace(*p)
		return &t
	}
	b.Title, b.Body, b.ApplyIt, b.Topic, b.CategoryID = trim(b.Title), trim(b.Body), trim(b.ApplyIt), trim(b.Topic), trim(b.CategoryID)
	if create {
		if b.Title == nil || b.Body == nil || b.Topic == nil {
			return bad("title, body and topic are required")
		}
		if b.ApplyIt == nil {
			empty := ""
			b.ApplyIt = &empty
		}
	}
	if b.Title != nil && (*b.Title == "" || utf8.RuneCountInString(*b.Title) > maxCardTitle) {
		return bad("title must be 1 to 120 characters")
	}
	if b.Body != nil && (*b.Body == "" || utf8.RuneCountInString(*b.Body) > maxCardBody) {
		return bad("body must be 1 to 1,500 characters")
	}
	if b.ApplyIt != nil && utf8.RuneCountInString(*b.ApplyIt) > maxCardApplyIt {
		return bad("apply it must be at most 400 characters")
	}
	if b.Topic != nil && !content.IsTopic(*b.Topic) {
		return bad("unknown topic")
	}
	if b.Audience != nil && !slices.Contains(store.Audiences, *b.Audience) {
		return bad("audience must be everyone, followers or private")
	}
	return store.MemberCardInput{Title: b.Title, Body: b.Body, ApplyIt: b.ApplyIt, Topic: b.Topic, CategoryID: b.CategoryID, Audience: b.Audience}, true
}

func (s *Server) myCards(w http.ResponseWriter, r *http.Request) {
	offset, limit, ok := offsetPage(w, r, 50)
	if !ok {
		return
	}
	cards, err := s.Store.MemberCards(r.Context(), store.MemberCardsParams{AuthorID: userID(r), CategoryID: r.URL.Query().Get("category"),
		All: true, Offset: offset, Limit: limit})
	if err != nil {
		s.fail(w, r, err, "cards")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": cards, "next_cursor": nextOffset(len(cards), offset, limit)})
}

func (s *Server) createMyCard(w http.ResponseWriter, r *http.Request) {
	var b memberCardBody
	if !decode(w, r, &b) {
		return
	}
	in, ok := b.input(w, true)
	if !ok {
		return
	}
	c, err := s.Store.CreateMemberCard(r.Context(), userID(r), in)
	if err != nil {
		s.limitReached(w, r, err, "cards")
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) myCard(w http.ResponseWriter, r *http.Request) {
	c, err := s.Store.MemberCard(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) updateMyCard(w http.ResponseWriter, r *http.Request) {
	var b memberCardBody
	if !decode(w, r, &b) {
		return
	}
	in, ok := b.input(w, false)
	if !ok {
		return
	}
	c, err := s.Store.UpdateMemberCard(r.Context(), userID(r), r.PathValue("id"), in)
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) deleteMyCard(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DeleteMemberCard(r.Context(), userID(r), r.PathValue("id")); err != nil {
		s.fail(w, r, err, "card")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// userCards lists the cards a member wrote that the viewer may see, with their categories.
func (s *Server) userCards(w http.ResponseWriter, r *http.Request) {
	p, err := s.Store.ProfileByHandle(r.Context(), r.PathValue("handle"), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	offset, limit, ok := offsetPage(w, r, 20)
	if !ok {
		return
	}
	posts, err := s.Store.MemberPosts(r.Context(), p.ID, r.URL.Query().Get("category"), userID(r), offset, limit)
	if err != nil {
		s.fail(w, r, err, "cards")
		return
	}
	out := map[string]any{"posts": posts, "next_cursor": nextOffset(len(posts), offset, limit)}
	if offset == 0 {
		cats, err := s.Store.MemberCategories(r.Context(), p.ID, false)
		if err != nil {
			s.fail(w, r, err, "categories")
			return
		}
		shown := []store.MemberCategory{}
		for _, c := range cats {
			if *c.CardCount > 0 {
				shown = append(shown, c)
			}
		}
		out["categories"] = shown
	}
	writeJSON(w, http.StatusOK, out)
}

// --- reports and moderation ---

func (s *Server) reportPost(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Reason string `json:"reason"`
	}
	if r.ContentLength != 0 && !decode(w, r, &in) {
		return
	}
	if utf8.RuneCountInString(in.Reason) > 300 {
		writeError(w, http.StatusBadRequest, "bad_request", "reason must be at most 300 characters")
		return
	}
	if err := s.Store.ReportCard(r.Context(), userID(r), r.PathValue("id"), strings.TrimSpace(in.Reason)); err != nil {
		s.fail(w, r, err, "card")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) reportedCards(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ReportedCards(r.Context())
	if err != nil {
		s.fail(w, r, err, "cards")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": list})
}

func (s *Server) moderateCard(hide bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := s.Store.ModerateCard(r.Context(), r.PathValue("id"), hide); err != nil {
			s.fail(w, r, err, "card")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// --- the card studio: AI media for member cards ---

func (s *Server) studio(w http.ResponseWriter, r *http.Request) {
	out := map[string]any{
		"available":     s.AI != nil,
		"rates":         rebornai.MediaRates(),
		"video_scenes":  rebornai.VideoScenes,
		"voices":        store.Voices,
		"audiences":     store.Audiences,
		"monthly_units": s.AIMonthlyUnits,
		"premium":       false,
		"wallet":        nil,
	}
	if uid := userID(r); uid != "" {
		u, err := s.Store.UserByID(r.Context(), uid)
		if err != nil {
			s.fail(w, r, err, "user")
			return
		}
		wallet, err := s.Store.AIWalletOf(r.Context(), uid, s.aiMonthly(u), s.Now())
		if err != nil {
			s.fail(w, r, err, "wallet")
			return
		}
		out["premium"], out["wallet"] = u.Premium, wallet
	}
	writeJSON(w, http.StatusOK, out)
}

// spokenText is what a card's audio and video narration read.
func spokenText(c store.Card) string {
	text := c.Title + ".\n\n" + c.Body
	if c.ApplyIt != "" {
		text += "\n\nApply it. " + c.ApplyIt
	}
	return text
}

func textHash(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "\n")))
	return hex.EncodeToString(sum[:8])
}

// studioJob checks the member may spend units on their card, runs run, saves
// what it made on the card and charges for it. run returns the media to save
// under kind and the charges to make.
func (s *Server) studioJob(w http.ResponseWriter, r *http.Request, kind string, units int,
	run func(ctx context.Context, u store.User, c store.Card) (any, []rebornai.Charge, error)) {
	u, ok := s.aiMember(w, r)
	if !ok {
		return
	}
	c, err := s.Store.MemberCard(r.Context(), u.ID, r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	monthly := s.aiMonthly(u)
	wallet, err := s.Store.AIWalletOf(r.Context(), u.ID, monthly, s.Now())
	if err != nil {
		s.fail(w, r, err, "wallet")
		return
	}
	if units < 0 {
		units = 0
	}
	if wallet.Remaining < units {
		s.outOfUnits(w, wallet)
		return
	}
	if !s.aiAllow(w, r) {
		return
	}
	// The work carries on if the member leaves the screen, so it is never paid
	// for and then lost.
	ctx := context.WithoutCancel(r.Context())
	media, charges, err := run(ctx, u, c)
	if rebornai.IsModerationBlock(err) {
		writeError(w, http.StatusUnprocessableEntity, "declined", "that can't be made; try describing it differently")
		return
	}
	if err != nil {
		s.aiFailed(w, r, err)
		return
	}
	card, err := s.Store.SetMemberMedia(ctx, u.ID, c.ID, kind, media)
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	spent := 0
	for _, ch := range charges {
		if ch.Units <= 0 {
			continue
		}
		var sp store.AISpend
		if sp, wallet, err = s.Store.SpendAIUnits(ctx, u.ID, ch.Kind, ch.Units, nil, monthly, s.Now()); err != nil {
			s.fail(w, r, err, "wallet")
			return
		}
		spent += sp.Units
	}
	writeJSON(w, http.StatusOK, map[string]any{"card": card, "units": spent, "wallet": wallet})
}

func (s *Server) makeCardImage(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Style  string `json:"style"`
		Prompt string `json:"prompt"`
		Shape  string `json:"shape"`
	}
	if !decode(w, r, &in) {
		return
	}
	switch in.Style {
	case rebornai.KindSketch, rebornai.KindIllustration, rebornai.KindPicture:
	default:
		writeError(w, http.StatusBadRequest, "bad_request", "style must be sketch, illustration or picture")
		return
	}
	switch in.Shape {
	case "":
		in.Shape = "landscape"
	case "square", "portrait", "landscape":
	default:
		writeError(w, http.StatusBadRequest, "bad_request", "shape must be square, portrait or landscape")
		return
	}
	in.Prompt = strings.TrimSpace(in.Prompt)
	if utf8.RuneCountInString(in.Prompt) > maxImagePrompt {
		writeError(w, http.StatusBadRequest, "bad_request", "describe the image in at most 1,000 characters")
		return
	}
	units := rebornai.UnitsFor(in.Style)
	s.studioJob(w, r, "image", units, func(ctx context.Context, u store.User, c store.Card) (any, []rebornai.Charge, error) {
		prompt := in.Prompt
		if prompt == "" {
			prompt = rebornai.CardPrompt(c.Title, c.Body)
		}
		url, width, height, err := s.AI.CardImage(ctx, u.ID, in.Style, prompt, in.Shape)
		if err != nil {
			return nil, nil, err
		}
		return store.MemberImage{URL: url, Style: in.Style, Width: width, Height: height, Prompt: in.Prompt},
			[]rebornai.Charge{{Kind: in.Style, Units: units}}, nil
	})
}

// voiceOf reads the optional voice field; the default is Heart.
func voiceOf(w http.ResponseWriter, r *http.Request) (string, bool) {
	var in struct {
		Voice string `json:"voice"`
	}
	if r.ContentLength != 0 && !decode(w, r, &in) {
		return "", false
	}
	if in.Voice == "" {
		in.Voice = "af_heart"
	}
	if store.VoiceName(in.Voice) == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown voice")
		return "", false
	}
	return in.Voice, true
}

func (s *Server) cardForUnits(r *http.Request) (store.Card, bool) {
	c, err := s.Store.MemberCard(r.Context(), userID(r), r.PathValue("id"))
	return c, err == nil
}

func (s *Server) makeCardAudio(w http.ResponseWriter, r *http.Request) {
	voice, ok := voiceOf(w, r)
	if !ok {
		return
	}
	units := 0
	if c, ok := s.cardForUnits(r); ok {
		units = rebornai.AudioUnits(spokenText(c))
	}
	s.studioJob(w, r, "audio", units, func(ctx context.Context, u store.User, c store.Card) (any, []rebornai.Charge, error) {
		text := spokenText(c)
		hash := textHash(text, voice)
		url, err := s.AI.SpeakAs(ctx, "ai/cards/"+c.ID+"/"+hash+".mp3", text, voice)
		if err != nil {
			return nil, nil, err
		}
		return store.MemberAudio{URL: url, Voice: voice, DurationS: store.SpokenSeconds(text), TextHash: hash},
			[]rebornai.Charge{{Kind: rebornai.KindAudio, Units: rebornai.AudioUnits(text)}}, nil
	})
}

func (s *Server) makeCardVideo(w http.ResponseWriter, r *http.Request) {
	voice, ok := voiceOf(w, r)
	if !ok {
		return
	}
	units := 0
	if c, ok := s.cardForUnits(r); ok {
		units = rebornai.VideoUnits(spokenText(c))
	}
	s.studioJob(w, r, "video", units, func(ctx context.Context, u store.User, c store.Card) (any, []rebornai.Charge, error) {
		text := spokenText(c)
		hash := textHash(text, voice)
		prompts := s.AI.ScenePrompts(ctx, u.ID, c.Title, c.Body)
		images, err := s.AI.VideoImages(ctx, u.ID, prompts)
		if err != nil {
			return nil, nil, err
		}
		audioURL, err := s.AI.SpeakAs(ctx, "ai/cards/"+c.ID+"/"+hash+".mp3", text, voice)
		if err != nil {
			return nil, nil, err
		}
		v := store.MemberVideo{Kind: "illustrated", AudioURL: audioURL, Voice: voice, DurationS: store.SpokenSeconds(text), TextHash: hash}
		for _, im := range images {
			v.Scenes = append(v.Scenes, store.VideoScene{URL: im.URL, Width: im.Width, Height: im.Height})
		}
		return v, []rebornai.Charge{{Kind: rebornai.KindVideo, Units: rebornai.VideoUnits(text)}}, nil
	})
}

func (s *Server) deleteCardMedia(w http.ResponseWriter, r *http.Request) {
	kind := r.PathValue("kind")
	if kind != "image" && kind != "audio" && kind != "video" {
		writeError(w, http.StatusNotFound, "not_found", "media not found")
		return
	}
	c, err := s.Store.SetMemberMedia(r.Context(), userID(r), r.PathValue("id"), kind, nil)
	if err != nil {
		s.fail(w, r, err, "card")
		return
	}
	writeJSON(w, http.StatusOK, c)
}
