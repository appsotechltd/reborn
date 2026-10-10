// Package push sends notifications to phones and browsers through Firebase
// Cloud Messaging (HTTP v1 API).
package push

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/appsotechltd/reborn/backend/internal/googleauth"
)

// Message is one notification.
type Message struct {
	Title string
	Body  string
	Data  map[string]string // e.g. {"post_id": "..."}, read by the app when tapped
}

// Sender delivers a message to one device token.
type Sender interface {
	Send(ctx context.Context, token string, m Message) error
}

// ErrUnregistered means the token is no longer valid and should be forgotten.
var ErrUnregistered = errors.New("device token is no longer registered")

// FCM sends through Firebase Cloud Messaging.
type FCM struct {
	SA      *googleauth.ServiceAccount
	BaseURL string // defaults to https://fcm.googleapis.com
}

// NewFCM reads a Firebase service account key.
func NewFCM(key []byte) (*FCM, error) {
	sa, err := googleauth.Parse(key, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, err
	}
	if sa.ProjectID == "" {
		return nil, fmt.Errorf("firebase service account key has no project_id")
	}
	return &FCM{SA: sa}, nil
}

// Send delivers m to token.
func (f *FCM) Send(ctx context.Context, token string, m Message) error {
	access, err := f.SA.Token(ctx)
	if err != nil {
		return err
	}
	body, _ := json.Marshal(map[string]any{"message": map[string]any{
		"token":        token,
		"notification": map[string]string{"title": m.Title, "body": m.Body},
		"data":         m.Data,
	}})
	base := f.BaseURL
	if base == "" {
		base = "https://fcm.googleapis.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1/projects/"+f.SA.ProjectID+"/messages:send", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+access)
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.SA.Client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	switch {
	case resp.StatusCode == http.StatusOK:
		return nil
	case resp.StatusCode == http.StatusNotFound || bytes.Contains(raw, []byte("UNREGISTERED")):
		return ErrUnregistered
	default:
		return fmt.Errorf("fcm: %s: %s", resp.Status, raw)
	}
}
