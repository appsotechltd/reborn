package agent

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/anthropics/anthropic-sdk-go/option"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

type fakeLib struct{ cards map[string]store.Card }

func (f fakeLib) Search(_ context.Context, p store.SearchParams) ([]store.Card, error) {
	var out []store.Card
	for _, c := range f.cards {
		if strings.Contains(strings.ToLower(c.Title+" "+c.Body), strings.ToLower(p.Query)) {
			out = append(out, c)
		}
	}
	return out, nil
}

func (f fakeLib) SourceCards(context.Context, string) (content.Source, []store.Card, error) {
	return content.Source{}, nil, store.ErrNotFound
}

func card(id, title, body string) store.Card {
	return store.Card{ID: id, Title: title, Body: body, ApplyIt: "Try it.", Topic: "health", Credit: "Source: Test"}
}

func TestChatCitesOnlyRetrievedCards(t *testing.T) {
	lib := fakeLib{cards: map[string]store.Card{
		"sleep--01":    card("sleep--01", "Regular wake time", "Wake at the same time daily."),
		"caffeine--01": card("caffeine--01", "Cut caffeine", "Avoid caffeine after lunch."),
	}}
	var mu sync.Mutex
	var bodies []map[string]any
	var betas []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		mu.Lock()
		bodies = append(bodies, body)
		betas = append(betas, r.Header.Get("anthropic-beta"))
		n := len(bodies)
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if n == 1 {
			_, _ = io.WriteString(w, `{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5",
				"content":[{"type":"tool_use","id":"toolu_1","name":"search_library","input":{"query":"caffeine"}}],
				"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}}`)
			return
		}
		_, _ = io.WriteString(w, `{"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-5-5",
			"content":[{"type":"text","text":"Wake at a steady time [sleep--01] and skip late coffee [caffeine--01]. Also [made-up--01]."}],
			"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}}`)
	}))
	defer srv.Close()

	a := New("test-key", "claude-opus-5-5", lib, nil, option.WithBaseURL(srv.URL), option.WithMaxRetries(0))
	reply, err := a.Chat(context.Background(), []Message{{Role: "user", Content: "wake"}})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, c := range reply.Citations {
		got = append(got, c.ID)
	}
	if strings.Join(got, ",") != "sleep--01,caffeine--01" {
		t.Fatalf("citations = %v", got)
	}
	if len(bodies) != 2 {
		t.Fatalf("requests = %d", len(bodies))
	}
	first := bodies[0]
	if first["model"] != "claude-opus-5-5" || first["fallbacks"] != "default" {
		t.Fatalf("request = %v", first)
	}
	if !strings.Contains(betas[0], "server-side-fallback-2026-07-01") {
		t.Fatalf("beta header = %q", betas[0])
	}
	if _, ok := first["thinking"]; ok {
		t.Fatal("thinking must be left unset")
	}
	msgs, _ := json.Marshal(first["messages"])
	if !strings.Contains(string(msgs), "[sleep--01] Regular wake time") {
		t.Fatalf("initial retrieval missing from prompt: %s", msgs)
	}
	second, _ := json.Marshal(bodies[1]["messages"])
	if !strings.Contains(string(second), "[caffeine--01] Cut caffeine") {
		t.Fatalf("tool result missing: %s", second)
	}
}

func TestValidate(t *testing.T) {
	bad := [][]Message{
		nil,
		{{Role: "assistant", Content: "hi"}},
		{{Role: "user", Content: "a"}, {Role: "assistant", Content: "b"}},
		{{Role: "user", Content: "  "}},
		{{Role: "user", Content: "a"}, {Role: "user", Content: "b"}},
	}
	for i, h := range bad {
		if validate(h) == nil {
			t.Errorf("case %d accepted", i)
		}
	}
	if err := validate([]Message{{Role: "user", Content: "a"}, {Role: "assistant", Content: "b"}, {Role: "user", Content: "c"}}); err != nil {
		t.Fatal(err)
	}
}
