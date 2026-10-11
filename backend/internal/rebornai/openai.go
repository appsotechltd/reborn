package rebornai

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"
)

// OpenAI is a small client for the parts of OpenAI's REST API Reborn AI uses:
// the Responses API (chat with function calling), image generation,
// transcription and text to speech.
type OpenAI struct {
	APIKey  string
	BaseURL string // defaults to https://api.openai.com
	HTTP    *http.Client
}

// APIError is an error response from OpenAI.
type APIError struct {
	Status  int
	Code    string
	Message string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("openai: %d %s: %s", e.Status, e.Code, e.Message)
}

// IsModerationBlock reports whether OpenAI refused a request on safety grounds.
func IsModerationBlock(err error) bool {
	var ae *APIError
	return errors.As(err, &ae) && (ae.Code == "moderation_blocked" || ae.Code == "content_policy_violation")
}

func (o *OpenAI) send(ctx context.Context, path, contentType string, body []byte) (*http.Response, error) {
	base := o.BaseURL
	if base == "" {
		base = "https://api.openai.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+o.APIKey)
	req.Header.Set("Content-Type", contentType)
	client := o.HTTP
	if client == nil {
		client = &http.Client{Timeout: 3 * time.Minute}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode/100 != 2 {
		defer resp.Body.Close()
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
		var e struct {
			Error struct {
				Code    any    `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.Unmarshal(raw, &e)
		code, _ := e.Error.Code.(string)
		msg := e.Error.Message
		if msg == "" {
			msg = string(raw)
		}
		return nil, &APIError{Status: resp.StatusCode, Code: code, Message: msg}
	}
	return resp, nil
}

func (o *OpenAI) postJSON(ctx context.Context, path string, in, out any) error {
	body, err := json.Marshal(in)
	if err != nil {
		return err
	}
	resp, err := o.send(ctx, path, "application/json", body)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return json.NewDecoder(io.LimitReader(resp.Body, 64<<20)).Decode(out)
}

// --- Responses API ---

// Tool is a function the model may call.
type Tool struct {
	Type        string          `json:"type"` // "function"
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
	Strict      bool            `json:"strict"`
}

// ResponseRequest is a call to POST /v1/responses.
type ResponseRequest struct {
	Model           string            `json:"model"`
	Instructions    string            `json:"instructions,omitempty"`
	Input           []json.RawMessage `json:"input"`
	Tools           []Tool            `json:"tools,omitempty"`
	Store           bool              `json:"store"`
	Include         []string          `json:"include,omitempty"`
	Reasoning       *Reasoning        `json:"reasoning,omitempty"`
	MaxOutputTokens int               `json:"max_output_tokens,omitempty"`
	User            string            `json:"safety_identifier,omitempty"`
}

// Reasoning sets how hard a reasoning model thinks.
type Reasoning struct {
	Effort string `json:"effort"`
}

// Response is the part of a Responses API result Reborn AI reads.
type Response struct {
	Status string            `json:"status"`
	Output []json.RawMessage `json:"output"`
	Usage  struct {
		InputTokens        int `json:"input_tokens"`
		OutputTokens       int `json:"output_tokens"`
		InputTokensDetails struct {
			CachedTokens int `json:"cached_tokens"`
		} `json:"input_tokens_details"`
	} `json:"usage"`
}

// OutputItem is one item of a response's output.
type OutputItem struct {
	Type      string `json:"type"`
	Name      string `json:"name"`
	CallID    string `json:"call_id"`
	Arguments string `json:"arguments"`
	Content   []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
}

// Respond runs one model call.
func (o *OpenAI) Respond(ctx context.Context, in ResponseRequest) (Response, error) {
	var out Response
	err := o.postJSON(ctx, "/v1/responses", in, &out)
	return out, err
}

// --- images ---

// ImageRequest is a call to POST /v1/images/generations.
type ImageRequest struct {
	Model        string `json:"model"`
	Prompt       string `json:"prompt"`
	Size         string `json:"size"`
	Quality      string `json:"quality"`
	OutputFormat string `json:"output_format"`
	Compression  int    `json:"output_compression,omitempty"` // 0-100, for jpeg and webp
	N            int    `json:"n"`
	User         string `json:"user,omitempty"`
}

// GenerateImage returns the image's bytes.
func (o *OpenAI) GenerateImage(ctx context.Context, in ImageRequest) ([]byte, error) {
	in.N = 1
	var out struct {
		Data []struct {
			B64JSON string `json:"b64_json"`
		} `json:"data"`
	}
	if err := o.postJSON(ctx, "/v1/images/generations", in, &out); err != nil {
		return nil, err
	}
	if len(out.Data) == 0 || out.Data[0].B64JSON == "" {
		return nil, errors.New("openai: no image returned")
	}
	return base64.StdEncoding.DecodeString(out.Data[0].B64JSON)
}

// --- audio ---

// Transcribe turns speech into text.
func (o *OpenAI) Transcribe(ctx context.Context, model, filename string, audio []byte) (string, error) {
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	_ = mw.WriteField("model", model)
	_ = mw.WriteField("response_format", "json")
	fw, err := mw.CreateFormFile("file", filename)
	if err != nil {
		return "", err
	}
	if _, err := fw.Write(audio); err != nil {
		return "", err
	}
	if err := mw.Close(); err != nil {
		return "", err
	}
	resp, err := o.send(ctx, "/v1/audio/transcriptions", mw.FormDataContentType(), buf.Bytes())
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var out struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	return out.Text, nil
}

// SpeechRequest is a call to POST /v1/audio/speech.
type SpeechRequest struct {
	Model          string `json:"model"`
	Voice          string `json:"voice"`
	Input          string `json:"input"`
	Instructions   string `json:"instructions,omitempty"`
	ResponseFormat string `json:"response_format"`
}

// Speak returns MP3 audio of the text.
func (o *OpenAI) Speak(ctx context.Context, in SpeechRequest) ([]byte, error) {
	in.ResponseFormat = "mp3"
	body, err := json.Marshal(in)
	if err != nil {
		return nil, err
	}
	resp, err := o.send(ctx, "/v1/audio/speech", "application/json", body)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(io.LimitReader(resp.Body, 32<<20))
}
