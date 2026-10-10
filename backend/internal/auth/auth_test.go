package auth

import (
	"testing"
	"time"
)

func TestPassword(t *testing.T) {
	h, err := HashPassword("correct horse")
	if err != nil {
		t.Fatal(err)
	}
	if !CheckPassword(h, "correct horse") || CheckPassword(h, "wrong") {
		t.Fatal("password check is wrong")
	}
}

func TestTokenRoundTrip(t *testing.T) {
	tk := NewTokens("secret")
	s, err := tk.Issue("user-1")
	if err != nil {
		t.Fatal(err)
	}
	if id, err := tk.Verify(s); err != nil || id != "user-1" {
		t.Fatalf("Verify = %q, %v", id, err)
	}
	if _, err := NewTokens("other").Verify(s); err == nil {
		t.Fatal("token verified with the wrong secret")
	}
	if _, err := tk.Verify("garbage"); err == nil {
		t.Fatal("garbage verified")
	}
}

func TestTokenExpiry(t *testing.T) {
	now := time.Now()
	tk := NewTokens("secret")
	tk.Now = func() time.Time { return now }
	s, _ := tk.Issue("u")
	tk.Now = func() time.Time { return now.Add(TokenTTL + time.Minute) }
	if _, err := tk.Verify(s); err == nil {
		t.Fatal("expired token verified")
	}
}
