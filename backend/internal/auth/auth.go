// Package auth hashes passwords and issues and verifies session tokens.
package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// TokenTTL is how long a session token is valid.
const TokenTTL = 30 * 24 * time.Hour

// ErrInvalidToken is returned for a missing, malformed, expired or forged token.
var ErrInvalidToken = errors.New("invalid token")

// HashPassword returns a bcrypt hash.
func HashPassword(pw string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
	return string(b), err
}

// CheckPassword reports whether pw matches hash.
func CheckPassword(hash, pw string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pw)) == nil
}

// Tokens signs and verifies HS256 session tokens.
type Tokens struct {
	Secret []byte
	Now    func() time.Time
}

// NewTokens returns a Tokens using secret.
func NewTokens(secret string) *Tokens { return &Tokens{Secret: []byte(secret), Now: time.Now} }

// Issue returns a token for userID.
func (t *Tokens) Issue(userID string) (string, error) {
	now := t.Now()
	claims := jwt.RegisteredClaims{
		Subject:   userID,
		Issuer:    "reborn",
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(TokenTTL)),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.Secret)
}

// Verify returns the user id in a valid token.
func (t *Tokens) Verify(token string) (string, error) {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(token, &claims, func(*jwt.Token) (any, error) { return t.Secret, nil },
		jwt.WithValidMethods([]string{"HS256"}), jwt.WithIssuer("reborn"), jwt.WithTimeFunc(t.Now), jwt.WithExpirationRequired())
	if err != nil || claims.Subject == "" {
		return "", ErrInvalidToken
	}
	return claims.Subject, nil
}
