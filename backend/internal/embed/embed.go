// Package embed turns text into vectors for semantic search.
package embed

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Dimensions is the vector size stored in cards.embedding.
const Dimensions = 1024

// Embedder produces one vector per input text.
type Embedder interface {
	Model() string
	// Embed embeds texts; inputType is "document" or "query".
	Embed(ctx context.Context, texts []string, inputType string) ([][]float32, error)
}

// Voyage calls the Voyage AI embeddings API.
type Voyage struct {
	APIKey  string
	ModelID string
	BaseURL string
	HTTP    *http.Client
}

// NewVoyage returns a Voyage embedder, or nil when apiKey is empty.
func NewVoyage(apiKey, model string) Embedder {
	if apiKey == "" {
		return nil
	}
	return &Voyage{APIKey: apiKey, ModelID: model, BaseURL: "https://api.voyageai.com/v1", HTTP: &http.Client{Timeout: 60 * time.Second}}
}

// Model returns the model id.
func (v *Voyage) Model() string { return v.ModelID }

// Embed implements Embedder.
func (v *Voyage) Embed(ctx context.Context, texts []string, inputType string) ([][]float32, error) {
	body, err := json.Marshal(map[string]any{
		"input":            texts,
		"model":            v.ModelID,
		"input_type":       inputType,
		"output_dimension": Dimensions,
	})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, v.BaseURL+"/embeddings", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+v.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := v.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("voyage: %s: %s", resp.Status, bytes.TrimSpace(raw))
	}
	var out struct {
		Data []struct {
			Embedding []float32 `json:"embedding"`
			Index     int       `json:"index"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	vecs := make([][]float32, len(texts))
	for _, d := range out.Data {
		if d.Index < 0 || d.Index >= len(vecs) {
			return nil, fmt.Errorf("voyage: index %d out of range", d.Index)
		}
		vecs[d.Index] = d.Embedding
	}
	for i, v := range vecs {
		if len(v) != Dimensions {
			return nil, fmt.Errorf("voyage: embedding %d has %d dimensions, want %d", i, len(v), Dimensions)
		}
	}
	return vecs, nil
}
