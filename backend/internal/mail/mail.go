// Package mail sends transactional email over SMTP.
package mail

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/smtp"
	"net/url"
	"strings"
	"time"
)

// Sender sends one plain-text email.
type Sender interface {
	Send(ctx context.Context, to, subject, body string) error
}

// FromURL returns an SMTP sender for smtp://user:pass@host:port; net/smtp
// upgrades to TLS with STARTTLS when the server offers it, so use port 587.
// An empty URL returns a sender that writes the email to the log, for development.
func FromURL(raw, from string) (Sender, error) {
	if raw == "" {
		return LogSender{}, nil
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "smtp" || u.Host == "" {
		return nil, fmt.Errorf("SMTP_URL must look like smtp://user:pass@host:587")
	}
	s := &SMTP{Addr: u.Host, From: from}
	if u.User != nil {
		pw, _ := u.User.Password()
		host, _, _ := net.SplitHostPort(u.Host)
		s.Auth = smtp.PlainAuth("", u.User.Username(), pw, host)
	}
	return s, nil
}

// SMTP sends through an SMTP server.
type SMTP struct {
	Addr string
	From string
	Auth smtp.Auth
}

// Send delivers the message.
func (s *SMTP) Send(ctx context.Context, to, subject, body string) error {
	if strings.ContainsAny(to+subject, "\r\n") {
		return fmt.Errorf("mail: header contains a newline")
	}
	msg := strings.Join([]string{
		"From: " + s.From,
		"To: " + to,
		"Subject: " + subject,
		"Date: " + time.Now().Format(time.RFC1123Z),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=utf-8",
		"",
		body,
	}, "\r\n")
	done := make(chan error, 1)
	go func() { done <- smtp.SendMail(s.Addr, s.Auth, addrOf(s.From), []string{to}, []byte(msg)) }()
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}

func addrOf(from string) string {
	if i := strings.LastIndex(from, "<"); i >= 0 {
		return strings.Trim(from[i:], "<>")
	}
	return from
}

// LogSender logs emails instead of sending them.
type LogSender struct{}

// Send logs the message.
func (LogSender) Send(_ context.Context, to, subject, body string) error {
	slog.Info("email (SMTP_URL not set, so not sent)", "to", to, "subject", subject, "body", body)
	return nil
}
