package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/rebornai"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

// Reborn AI is the premium assistant. Premium includes AIMonthlyUnits a
// month; members can buy top-up packs when they run out. Every action spends
// units at its own rate (rebornai.Rates).

// aiHistoryTurns is how many earlier messages each reply sees.
const aiHistoryTurns = 20

// maxVoiceBytes caps a voice message upload (about 10 minutes of compressed speech).
const maxVoiceBytes = 10 << 20

func (s *Server) aiMonthly(u store.User) int {
	if u.Premium {
		return s.AIMonthlyUnits
	}
	return 0
}

func (s *Server) aiStatus(w http.ResponseWriter, r *http.Request) {
	out := map[string]any{
		"available": s.AI != nil,
		"rates":     rebornai.Rates,
		"packs":     payments.UnitPacks,
		"providers": map[string]bool{"stripe": s.Stripe != nil, "apple": s.Apple != nil, "google": s.Google != nil},
		"premium":   false,
		"wallet":    nil,
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

// aiMember checks that Reborn AI is on and the user is premium.
func (s *Server) aiMember(w http.ResponseWriter, r *http.Request) (store.User, bool) {
	if s.AI == nil {
		writeError(w, http.StatusServiceUnavailable, "ai_unavailable", "Reborn AI is not set up on this server")
		return store.User{}, false
	}
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return store.User{}, false
	}
	if !u.Premium {
		writeError(w, http.StatusForbidden, "premium_required", "Reborn AI is part of premium")
		return store.User{}, false
	}
	return u, true
}

func (s *Server) outOfUnits(w http.ResponseWriter, wallet store.AIWallet) {
	writeJSON(w, http.StatusPaymentRequired, map[string]any{
		"error":  map[string]string{"code": "out_of_units", "message": "you've used all your AI units; top up to keep going"},
		"wallet": wallet,
	})
}

type aiTurnInput struct {
	ConversationID string
	Message        string
	Voice          bool
	VoiceUnits     int // what hearing the member's voice message cost
}

func (s *Server) aiChat(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ConversationID string `json:"conversation_id"`
		Message        string `json:"message"`
	}
	if !decode(w, r, &in) {
		return
	}
	in.Message = strings.TrimSpace(in.Message)
	if in.Message == "" || len(in.Message) > 8000 {
		writeError(w, http.StatusBadRequest, "bad_request", "message must be 1 to 8000 characters")
		return
	}
	s.aiTurn(w, r, aiTurnInput{ConversationID: in.ConversationID, Message: in.Message})
}

func (s *Server) aiVoice(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxVoiceBytes+1<<16)
	if err := r.ParseMultipartForm(maxVoiceBytes); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "send the recording as multipart form field \"audio\" (10 MB at most)")
		return
	}
	u, ok := s.aiMember(w, r)
	if !ok {
		return
	}
	f, hdr, err := r.FormFile("audio")
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "missing \"audio\" file")
		return
	}
	defer f.Close()
	audio, err := io.ReadAll(f)
	if err != nil || len(audio) == 0 {
		writeError(w, http.StatusBadRequest, "bad_request", "empty recording")
		return
	}
	ext := strings.ToLower(path.Ext(hdr.Filename))
	switch ext {
	case ".m4a", ".mp3", ".mp4", ".mpeg", ".mpga", ".wav", ".webm", ".ogg":
	default:
		writeError(w, http.StatusBadRequest, "bad_request", "audio must be m4a, mp3, mp4, wav, webm or ogg")
		return
	}
	wallet, err := s.Store.AIWalletOf(r.Context(), u.ID, s.aiMonthly(u), s.Now())
	if err != nil {
		s.fail(w, r, err, "wallet")
		return
	}
	// A voice turn costs at least a unit to hear it and a unit for the reply.
	if wallet.Remaining < 2 {
		s.outOfUnits(w, wallet)
		return
	}
	if !s.aiAllow(w, r) {
		return
	}
	text, err := s.AI.Transcribe(r.Context(), "voice"+ext, audio)
	if err != nil {
		s.aiFailed(w, r, err)
		return
	}
	if text == "" {
		writeError(w, http.StatusUnprocessableEntity, "no_speech", "we couldn't hear anything in that recording")
		return
	}
	s.aiTurn(w, r, aiTurnInput{ConversationID: r.FormValue("conversation_id"), Message: truncateRunes(text, 8000),
		Voice: true, VoiceUnits: max(1, rebornai.VoiceUnits(text))})
}

func (s *Server) aiAllow(w http.ResponseWriter, r *http.Request) bool {
	if !s.Cache.Allow(r.Context(), "ai:"+userID(r)+":"+s.Now().UTC().Format("2006010215"), s.AIHourly, time.Hour) {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "you've sent a lot of messages this hour; try again soon")
		return false
	}
	return true
}

func (s *Server) aiFailed(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, context.Canceled) {
		return
	}
	slog.Error("reborn ai", "path", r.URL.Path, "err", err)
	writeError(w, http.StatusBadGateway, "ai_failed", "Reborn AI couldn't answer right now, please try again")
}

// aiTurn answers one message (typed, or already transcribed) and charges for it.
func (s *Server) aiTurn(w http.ResponseWriter, r *http.Request, in aiTurnInput) {
	ctx := r.Context()
	u, ok := s.aiMember(w, r)
	if !ok {
		return
	}
	monthly := s.aiMonthly(u)
	wallet, err := s.Store.AIWalletOf(ctx, u.ID, monthly, s.Now())
	if err != nil {
		s.fail(w, r, err, "wallet")
		return
	}
	base := rebornai.UnitsFor(rebornai.KindText) + in.VoiceUnits
	if !in.Voice && wallet.Remaining < base { // a voice turn checked the balance before transcribing
		s.outOfUnits(w, wallet)
		return
	}
	if !in.Voice && !s.aiAllow(w, r) { // voice turns were counted before transcribing
		return
	}

	var conv store.AIConversation
	var history []rebornai.Turn
	if in.ConversationID != "" {
		if conv, err = s.Store.AIConversationOf(ctx, u.ID, in.ConversationID); err != nil {
			s.fail(w, r, err, "conversation")
			return
		}
		msgs, err := s.Store.AIMessages(ctx, conv.ID, aiHistoryTurns)
		if err != nil {
			s.fail(w, r, err, "conversation")
			return
		}
		for _, m := range msgs {
			history = append(history, rebornai.Turn{Role: m.Role, Content: m.Content})
		}
	}

	reply, err := s.AI.Chat(ctx, rebornai.Request{UserID: u.ID, History: history, Message: in.Message, Voice: in.Voice,
		Extras: max(wallet.Remaining-base, 0)})
	if err != nil {
		s.aiFailed(w, r, err)
		return
	}

	// Save the exchange, then charge for it. Saving uses a fresh context so a
	// member who closes the app mid-reply still gets the reply in their history.
	ctx = context.WithoutCancel(ctx)
	if conv.ID == "" {
		if conv, err = s.Store.CreateAIConversation(ctx, u.ID, truncateRunes(in.Message, 60), s.Now()); err != nil {
			s.fail(w, r, err, "conversation")
			return
		}
	}
	userMsg, err := s.Store.AddAIMessage(ctx, conv.ID, store.AIMessage{Role: "user", Content: in.Message, Voice: in.Voice, Units: in.VoiceUnits}, s.Now())
	if err != nil {
		s.fail(w, r, err, "message")
		return
	}
	ids := make([]string, len(reply.Citations))
	for i, c := range reply.Citations {
		ids[i] = c.ID
	}
	attachments, _ := json.Marshal(reply.Attachments)
	if reply.Attachments == nil {
		attachments = []byte("[]")
	}
	units := rebornai.UnitsFor(rebornai.KindText)
	for _, c := range reply.Charges {
		units += c.Units
	}
	msg, err := s.Store.AddAIMessage(ctx, conv.ID, store.AIMessage{Role: "assistant", Content: reply.Text, Voice: in.Voice,
		CitationIDs: ids, Citations: reply.Citations, Attachments: attachments, Units: units}, s.Now())
	if err != nil {
		s.fail(w, r, err, "message")
		return
	}
	charges := []rebornai.Charge{{Kind: rebornai.KindText, Units: rebornai.UnitsFor(rebornai.KindText)}}
	if in.VoiceUnits > 0 {
		charges = append(charges, rebornai.Charge{Kind: rebornai.KindVoice, Units: in.VoiceUnits})
	}
	charges = append(charges, reply.Charges...)
	for _, c := range charges {
		mid := msg.ID
		if c.Kind == rebornai.KindVoice {
			mid = userMsg.ID
		}
		if _, wallet, err = s.Store.SpendAIUnits(ctx, u.ID, c.Kind, c.Units, &mid, monthly, s.Now()); err != nil {
			s.fail(w, r, err, "wallet")
			return
		}
	}
	conv.UpdatedAt = msg.CreatedAt
	out := map[string]any{"conversation": conv, "user_message": userMsg, "message": msg, "wallet": wallet}
	if in.Voice {
		out["transcript"] = in.Message
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) aiSpeech(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	u, ok := s.aiMember(w, r)
	if !ok {
		return
	}
	m, err := s.Store.AIMessageOf(ctx, u.ID, r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "message")
		return
	}
	if m.Role != "assistant" {
		writeError(w, http.StatusBadRequest, "bad_request", "only Reborn AI's replies can be read aloud")
		return
	}
	// Listening is free: replies are read by our own Kokoro voice, and the
	// audio is saved so it is only ever made once.
	monthly := s.aiMonthly(u)
	wallet, err := s.Store.AIWalletOf(ctx, u.ID, monthly, s.Now())
	if err != nil {
		s.fail(w, r, err, "wallet")
		return
	}
	url, _, err := s.AI.Speak(ctx, "ai/speech/"+m.ID+".mp3", rebornai.Spoken(m.Content))
	if err != nil {
		s.aiFailed(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"url": url, "units": 0, "wallet": wallet})
}

func (s *Server) aiConversations(w http.ResponseWriter, r *http.Request) {
	convs, err := s.Store.AIConversations(r.Context(), userID(r), 50)
	if err != nil {
		s.fail(w, r, err, "conversations")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"conversations": convs})
}

func (s *Server) aiConversation(w http.ResponseWriter, r *http.Request) {
	conv, err := s.Store.AIConversationOf(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "conversation")
		return
	}
	msgs, err := s.Store.AIMessages(r.Context(), conv.ID, 200)
	if err != nil {
		s.fail(w, r, err, "conversation")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"conversation": conv, "messages": msgs})
}

func (s *Server) deleteAIConversation(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DeleteAIConversation(r.Context(), userID(r), r.PathValue("id")); err != nil {
		s.fail(w, r, err, "conversation")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) aiUsage(w http.ResponseWriter, r *http.Request) {
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return
	}
	wallet, err := s.Store.AIWalletOf(r.Context(), u.ID, s.aiMonthly(u), s.Now())
	if err != nil {
		s.fail(w, r, err, "wallet")
		return
	}
	usage, err := s.Store.AIUsage(r.Context(), u.ID, 100)
	if err != nil {
		s.fail(w, r, err, "usage")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"wallet": wallet, "usage": usage})
}

// --- top-ups ---

// topUpMember checks the user may buy units: top-ups are spent through Reborn AI, which needs premium.
func (s *Server) topUpMember(w http.ResponseWriter, r *http.Request) (store.User, bool) {
	u, err := s.Store.UserByID(r.Context(), userID(r))
	if err != nil {
		s.fail(w, r, err, "user")
		return u, false
	}
	if !u.Premium {
		writeError(w, http.StatusForbidden, "premium_required", "top-ups are for premium members")
		return u, false
	}
	return u, true
}

func (s *Server) topUpCheckout(w http.ResponseWriter, r *http.Request) {
	if s.Stripe == nil {
		writeError(w, http.StatusServiceUnavailable, "topups_unavailable", "web top-ups are not set up yet")
		return
	}
	var in struct {
		Pack string `json:"pack"`
	}
	if !decode(w, r, &in) {
		return
	}
	pack, ok := payments.PackByID(in.Pack)
	if !ok {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown pack")
		return
	}
	u, ok := s.topUpMember(w, r)
	if !ok {
		return
	}
	t, err := s.Store.CreatePendingTopUp(r.Context(), store.NewAITopUp{UserID: u.ID, Pack: pack.ID, Units: pack.Units,
		AmountCents: pack.AmountCents, Currency: pack.Currency, Provider: "stripe"})
	if err != nil {
		s.fail(w, r, err, "top-up")
		return
	}
	sessionID, checkoutURL, err := s.Stripe.CreateTopUpCheckout(r.Context(), payments.TopUpCheckout{
		TopUpID: t.ID, Pack: pack, Email: u.Email,
		SuccessURL: s.WebBaseURL + "/ai?topup=" + t.ID, CancelURL: s.WebBaseURL + "/ai",
	})
	if err != nil {
		slog.Error("stripe top-up checkout", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't start the payment, try again")
		return
	}
	if err := s.Store.SetTopUpRef(r.Context(), t.ID, sessionID); err != nil {
		s.fail(w, r, err, "top-up")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"topup_id": t.ID, "url": checkoutURL})
}

func (s *Server) topUp(w http.ResponseWriter, r *http.Request) {
	t, err := s.Store.TopUpOf(r.Context(), userID(r), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err, "top-up")
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (s *Server) topUpApple(w http.ResponseWriter, r *http.Request) {
	if s.Apple == nil {
		writeError(w, http.StatusServiceUnavailable, "topups_unavailable", "App Store top-ups are not set up yet")
		return
	}
	var in struct {
		SignedTransaction string `json:"signed_transaction"`
	}
	if !decode(w, r, &in) {
		return
	}
	u, ok := s.topUpMember(w, r)
	if !ok {
		return
	}
	tx, err := s.Apple.VerifyTransaction(in.SignedTransaction)
	if err != nil || (tx.AppAccountToken != "" && !strings.EqualFold(tx.AppAccountToken, u.ID)) {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the purchase could not be verified")
		return
	}
	s.recordStoreTopUp(w, r, u.ID, "apple", tx.ProductID, tx.TransactionID)
}

func (s *Server) topUpGoogle(w http.ResponseWriter, r *http.Request) {
	if s.Google == nil {
		writeError(w, http.StatusServiceUnavailable, "topups_unavailable", "Google Play top-ups are not set up yet")
		return
	}
	var in struct {
		ProductID     string `json:"product_id"`
		PurchaseToken string `json:"purchase_token"`
	}
	if !decode(w, r, &in) {
		return
	}
	if _, ok := payments.PackByProduct(in.ProductID); !ok || in.PurchaseToken == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "unknown product or missing purchase token")
		return
	}
	u, ok := s.topUpMember(w, r)
	if !ok {
		return
	}
	p, err := s.Google.VerifyPurchase(r.Context(), in.ProductID, in.PurchaseToken)
	if errors.Is(err, payments.ErrInvalid) {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "the purchase could not be verified")
		return
	}
	if err != nil {
		slog.Error("google play verify", "err", err)
		writeError(w, http.StatusBadGateway, "payment_error", "couldn't check the purchase, try again")
		return
	}
	s.recordStoreTopUp(w, r, u.ID, "google", in.ProductID, p.OrderID)
}

func (s *Server) recordStoreTopUp(w http.ResponseWriter, r *http.Request, uid, provider, productID, ref string) {
	pack, ok := payments.PackByProduct(productID)
	if !ok || ref == "" {
		writeError(w, http.StatusBadRequest, "invalid_purchase", "unknown product")
		return
	}
	t, err := s.Store.RecordPaidTopUp(r.Context(), store.NewAITopUp{UserID: uid, Pack: pack.ID, Units: pack.Units,
		AmountCents: pack.AmountCents, Currency: pack.Currency, Provider: provider}, ref, s.Now())
	if err != nil {
		s.fail(w, r, err, "top-up")
		return
	}
	writeJSON(w, http.StatusCreated, t)
}
