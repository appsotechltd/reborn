package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/objstore"
	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/rebornai"
)

// fakeOpenAI answers like OpenAI's API: it calls make_chart or make_image when
// the message asks for one, then replies citing a sleep card.
type fakeOpenAI struct {
	mu       sync.Mutex
	images   int
	speeches int
	inputs   [][]json.RawMessage
	prompts  []string
}

func (f *fakeOpenAI) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if r.Header.Get("Authorization") != "Bearer sk-test" {
		http.Error(w, `{"error":{"message":"bad key"}}`, 401)
		return
	}
	switch r.URL.Path {
	case "/v1/responses":
		var req rebornai.ResponseRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		f.inputs = append(f.inputs, req.Input)
		var last struct {
			Type    string `json:"type"`
			Role    string `json:"role"`
			Content any    `json:"content"`
		}
		_ = json.Unmarshal(req.Input[len(req.Input)-1], &last)
		ask, _ := last.Content.(string)
		switch {
		case last.Type == "function_call_output" || len(req.Tools) == 0:
			fmt.Fprint(w, `{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Here it is [nhs-sleep-tips--01]."}]}]}`)
		case strings.Contains(ask, "chart"):
			args, _ := json.Marshal(map[string]any{"kind": "bar", "title": "Sleep this week", "unit": "hours",
				"labels": []string{"Mon", "Tue"}, "series": []map[string]any{{"name": "Hours", "values": []float64{7, 6.5}}}})
			fmt.Fprintf(w, `{"status":"completed","output":[{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"x"},{"type":"function_call","call_id":"call_1","name":"make_chart","arguments":%q}]}`, args)
		case strings.Contains(ask, "picture"):
			args, _ := json.Marshal(map[string]any{"style": "picture", "prompt": "A calm bedroom at dusk", "shape": "portrait", "alt": "A bedroom"})
			fmt.Fprintf(w, `{"status":"completed","output":[{"type":"function_call","call_id":"call_2","name":"make_image","arguments":%q}]}`, args)
		default:
			fmt.Fprint(w, `{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Keep a steady wake time, even at weekends [nhs-sleep-tips--01]. Get daylight early."}]}]}`)
		}
	case "/v1/images/generations":
		var req rebornai.ImageRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		f.images++
		f.prompts = append(f.prompts, req.Model+" "+req.Quality+" "+req.Size)
		fmt.Fprintf(w, `{"data":[{"b64_json":%q}]}`, base64.StdEncoding.EncodeToString([]byte("webp-bytes")))
	case "/v1/audio/transcriptions":
		if err := r.ParseMultipartForm(1 << 20); err != nil || r.FormValue("model") != "gpt-4o-mini-transcribe" {
			http.Error(w, `{"error":{"message":"bad form"}}`, 400)
			return
		}
		fmt.Fprint(w, `{"text":"How do I sleep better tonight?"}`)
	case "/v1/audio/speech":
		f.speeches++
		w.Header().Set("Content-Type", "audio/mpeg")
		fmt.Fprint(w, "mp3-bytes")
	default:
		http.NotFound(w, r)
	}
}

func (h *harness) withAI(monthly int) *fakeOpenAI {
	f := &fakeOpenAI{}
	srv := httptest.NewServer(f)
	h.t.Cleanup(srv.Close)
	h.api.Media = &objstore.Local{Dir: h.t.TempDir(), BaseURL: "/media"}
	h.api.AI = &rebornai.Assistant{AI: &rebornai.OpenAI{APIKey: "sk-test", BaseURL: srv.URL}, Lib: h.st, Media: h.api.Media,
		Models: rebornai.DefaultModels, Now: func() time.Time { return h.now }}
	h.api.AIMonthlyUnits = monthly
	return f
}

func (h *harness) makePremium(token string) {
	id := h.do("GET", "/v1/me", token, nil, 200)["id"].(string)
	if err := h.st.GrantPremium(context.Background(), id, "test", 30, time.Now()); err != nil {
		h.t.Fatal(err)
	}
}

func wallet(m map[string]any) map[string]any { return m["wallet"].(map[string]any) }

func (h *harness) voice(token, convID string, want int) map[string]any {
	h.t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, _ := mw.CreateFormFile("audio", "note.m4a")
	fw.Write([]byte("m4a-bytes"))
	if convID != "" {
		mw.WriteField("conversation_id", convID)
	}
	mw.Close()
	req, _ := http.NewRequest("POST", h.srv.URL+"/v1/ai/voice", &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		h.t.Fatal(err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != want {
		h.t.Fatalf("voice = %d, want %d: %s", resp.StatusCode, want, raw)
	}
	out := map[string]any{}
	_ = json.Unmarshal(raw, &out)
	return out
}

func TestRebornAI(t *testing.T) {
	h := setup(t)
	ada, _ := h.registerAs("ada@example.com", "Ada")
	chat := func(token string, body map[string]any, want int) map[string]any {
		return h.do("POST", "/v1/ai/chat", token, body, want)
	}

	if out := h.do("GET", "/v1/ai", "", nil, 200); out["available"] != false || out["wallet"] != nil || len(list(out, "packs")) != 3 {
		t.Fatalf("status = %v", out)
	}
	chat(ada, map[string]any{"message": "hi"}, 503)
	f := h.withAI(20)
	chat(ada, map[string]any{"message": "hi"}, 403) // premium only
	h.do("POST", "/v1/ai/topups/checkout", ada, map[string]any{"pack": "units_250"}, 503)
	h.makePremium(ada)

	if w := wallet(h.do("GET", "/v1/ai", ada, nil, 200)); w["remaining"] != 20.0 || w["resets_at"] != "2026-11-01T00:00:00Z" {
		t.Fatalf("wallet = %v", w)
	}

	// A text reply costs 1 unit and cites the cards it used.
	out := chat(ada, map[string]any{"message": "How can I sleep better?"}, 200)
	msg := out["message"].(map[string]any)
	convID := out["conversation"].(map[string]any)["id"].(string)
	if msg["units"] != 1.0 || wallet(out)["remaining"] != 19.0 || len(list(msg, "citations")) != 1 ||
		!strings.Contains(msg["content"].(string), "steady wake time") {
		t.Fatalf("chat = %v", out)
	}

	// A chart costs 1 more; the earlier turns go to the model.
	out = chat(ada, map[string]any{"conversation_id": convID, "message": "Draw a chart of my sleep"}, 200)
	msg = out["message"].(map[string]any)
	att := list(msg, "attachments")
	if msg["units"] != 2.0 || wallet(out)["remaining"] != 17.0 || len(att) != 1 || att[0].(map[string]any)["type"] != "chart" {
		t.Fatalf("chart = %v", out)
	}
	if n := len(f.inputs[1]); n != 3 { // 2 history turns + the new message
		t.Fatalf("history sent = %d items", n)
	}
	if n := len(f.inputs[2]); n != 6 { // ... + reasoning, call, call output
		t.Fatalf("tool round input = %d items", n)
	}

	// A picture costs 12 more and is saved; asking again reuses it.
	out = chat(ada, map[string]any{"conversation_id": convID, "message": "Make a picture of a calm bedroom"}, 200)
	msg = out["message"].(map[string]any)
	img := list(msg, "attachments")[0].(map[string]any)
	if msg["units"] != 13.0 || wallet(out)["remaining"] != 4.0 || img["style"] != "picture" || !strings.HasPrefix(img["url"].(string), "/media/ai/images/") ||
		f.images != 1 || f.prompts[0] != "gpt-image-2 medium 1024x1536" {
		t.Fatalf("picture = %v, prompts %v", out, f.prompts)
	}
	// Not enough units for another: the reply still comes, for 1 unit, without the picture.
	out = chat(ada, map[string]any{"conversation_id": convID, "message": "Another picture please"}, 200)
	msg = out["message"].(map[string]any)
	if msg["units"] != 1.0 || wallet(out)["remaining"] != 3.0 || len(list(msg, "attachments")) != 0 || f.images != 1 {
		t.Fatalf("no units picture = %v", out)
	}

	// Voice: hearing the 6-word question is 1 unit, the reply 1 more.
	out = h.voice(ada, convID, 200)
	msg = out["message"].(map[string]any)
	if out["transcript"] != "How do I sleep better tonight?" || out["user_message"].(map[string]any)["units"] != 1.0 ||
		msg["voice"] != true || wallet(out)["remaining"] != 1.0 {
		t.Fatalf("voice = %v", out)
	}
	// Reading the reply aloud costs a unit per 30 words, once.
	path := "/v1/ai/messages/" + msg["id"].(string) + "/speech"
	sp := h.do("POST", path, ada, nil, 200)
	if sp["units"] != 1.0 || wallet(sp)["remaining"] != 0.0 || !strings.HasSuffix(sp["url"].(string), ".mp3") {
		t.Fatalf("speech = %v", sp)
	}
	if sp = h.do("POST", path, ada, nil, 200); sp["units"] != 0.0 || f.speeches != 1 {
		t.Fatalf("speech again = %v", sp)
	}

	// Out of units.
	if out = chat(ada, map[string]any{"message": "hi"}, 402); wallet(out)["remaining"] != 0.0 {
		t.Fatalf("402 = %v", out)
	}
	h.voice(ada, "", 402)

	// Top up on the web.
	var form string
	stripe := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		form = string(b)
		fmt.Fprint(w, `{"id":"cs_topup_1","url":"https://checkout.stripe.test/cs_topup_1"}`)
	}))
	defer stripe.Close()
	h.api.Stripe = &payments.Stripe{SecretKey: "sk_test", WebhookSecret: "whsec_test", BaseURL: stripe.URL, Now: func() time.Time { return h.now }}
	h.api.WebBaseURL = "https://reborn.test"
	h.do("POST", "/v1/ai/topups/checkout", ada, map[string]any{"pack": "units_9"}, 400)
	co := h.do("POST", "/v1/ai/topups/checkout", ada, map[string]any{"pack": "units_250"}, 201)
	topupID := co["topup_id"].(string)
	if !strings.Contains(form, "unit_amount%5D=299") || !strings.Contains(form, "topup_id%5D="+topupID) {
		t.Fatalf("checkout form = %s", form)
	}
	event := fmt.Sprintf(`{"type":"checkout.session.completed","data":{"object":{"id":"cs_topup_1","payment_status":"paid","metadata":{"topup_id":%q}}}}`, topupID)
	ts := h.now.Unix()
	mac := hmac.New(sha256.New, []byte("whsec_test"))
	fmt.Fprintf(mac, "%d.%s", ts, event)
	for range 2 { // a repeated webhook credits once
		req, _ := http.NewRequest("POST", h.srv.URL+"/v1/webhooks/stripe", strings.NewReader(event))
		req.Header.Set("Stripe-Signature", fmt.Sprintf("t=%d,v1=%s", ts, hex.EncodeToString(mac.Sum(nil))))
		resp, err := http.DefaultClient.Do(req)
		if err != nil || resp.StatusCode != 204 {
			t.Fatalf("webhook = %v %v", resp, err)
		}
		resp.Body.Close()
	}
	if tu := h.do("GET", "/v1/ai/topups/"+topupID, ada, nil, 200); tu["status"] != "paid" {
		t.Fatalf("top-up = %v", tu)
	}
	if w := wallet(h.do("GET", "/v1/ai", ada, nil, 200)); w["topup_units"] != 250.0 || w["remaining"] != 250.0 {
		t.Fatalf("after top-up = %v", w)
	}

	// Next month the allowance is back, and is spent before top-up units.
	h.now = time.Date(2026, 11, 2, 9, 0, 0, 0, time.UTC)
	out = chat(ada, map[string]any{"message": "How can I sleep better?"}, 200)
	if w := wallet(out); w["allowance_left"] != 19.0 || w["topup_units"] != 250.0 || w["remaining"] != 269.0 {
		t.Fatalf("new month = %v", w)
	}

	use := h.do("GET", "/v1/ai/usage", ada, nil, 200)
	if u := list(use, "usage"); len(u) != 10 || u[0].(map[string]any)["kind"] != "text" {
		t.Fatalf("usage = %v", u)
	}

	// Chats are private.
	convs := list(h.do("GET", "/v1/ai/conversations", ada, nil, 200), "conversations")
	if len(convs) != 2 {
		t.Fatalf("conversations = %v", convs)
	}
	got := h.do("GET", "/v1/ai/conversations/"+convID, ada, nil, 200)
	if n := len(list(got, "messages")); n != 10 {
		t.Fatalf("messages = %d", n)
	}
	bob, _ := h.registerAs("bob@example.com", "Bob")
	h.do("GET", "/v1/ai/conversations/"+convID, bob, nil, 404)
	h.do("POST", path, bob, nil, 403)
	h.makePremium(bob)
	h.do("POST", path, bob, nil, 404)
	chat(bob, map[string]any{"conversation_id": convID, "message": "hi"}, 404)
	h.do("DELETE", "/v1/ai/conversations/"+convID, bob, nil, 404)
	h.do("DELETE", "/v1/ai/conversations/"+convID, ada, nil, 204)
	h.do("GET", "/v1/ai/conversations/"+convID, ada, nil, 404)
}
