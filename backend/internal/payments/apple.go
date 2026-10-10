package payments

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"strings"
	"time"
)

// Apple verifies StoreKit 2 signed transactions (JWS) locally: the x5c chain
// must lead to Apple's root CA and the ES256 signature must match.
type Apple struct {
	BundleID string
	Roots    *x509.CertPool // Apple Root CA - G3
	Now      func() time.Time
}

// Apple's marker extensions on the leaf and intermediate certificates.
var (
	oidAppleLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidAppleIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

// AppleTransaction is the part of a signed transaction the API uses.
type AppleTransaction struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	BundleID              string `json:"bundleId"`
	ProductID             string `json:"productId"`
	Type                  string `json:"type"`
	Environment           string `json:"environment"`
	AppAccountToken       string `json:"appAccountToken"` // the app sets this to the user's id
	ExpiresDate           int64  `json:"expiresDate"`     // ms since epoch, for subscriptions
	RevocationDate        int64  `json:"revocationDate"`
}

// Expires returns a subscription transaction's end.
func (t AppleTransaction) Expires() time.Time { return time.UnixMilli(t.ExpiresDate) }

// VerifyTransaction checks a consumable's signedTransactionInfo JWS and
// returns its payload. Refunded transactions are rejected.
func (a *Apple) VerifyTransaction(jws string) (AppleTransaction, error) {
	tx, err := a.ParseTransaction(jws)
	if err == nil && tx.RevocationDate != 0 {
		return tx, ErrInvalid
	}
	return tx, err
}

// ParseTransaction checks a signedTransactionInfo JWS for this app and returns
// its payload, refunded or not.
func (a *Apple) ParseTransaction(jws string) (AppleTransaction, error) {
	var tx AppleTransaction
	payload, err := a.verifyJWS(jws)
	if err != nil {
		return tx, err
	}
	if err := json.Unmarshal(payload, &tx); err != nil {
		return tx, ErrInvalid
	}
	if tx.BundleID != a.BundleID || tx.TransactionID == "" {
		return tx, ErrInvalid
	}
	return tx, nil
}

// AppleNotification is an App Store Server Notification (V2).
type AppleNotification struct {
	Type        string
	Subtype     string
	Transaction AppleTransaction
}

// VerifyNotification checks a notification's signedPayload and the transaction inside it.
func (a *Apple) VerifyNotification(signedPayload string) (AppleNotification, error) {
	var n AppleNotification
	payload, err := a.verifyJWS(signedPayload)
	if err != nil {
		return n, err
	}
	var body struct {
		NotificationType string `json:"notificationType"`
		Subtype          string `json:"subtype"`
		Data             struct {
			BundleID              string `json:"bundleId"`
			SignedTransactionInfo string `json:"signedTransactionInfo"`
		} `json:"data"`
	}
	if err := json.Unmarshal(payload, &body); err != nil || body.Data.BundleID != a.BundleID {
		return n, ErrInvalid
	}
	n.Type, n.Subtype = body.NotificationType, body.Subtype
	if body.Data.SignedTransactionInfo != "" {
		if n.Transaction, err = a.ParseTransaction(body.Data.SignedTransactionInfo); err != nil {
			return n, err
		}
	}
	return n, nil
}

// verifyJWS checks the chain and signature of an App Store JWS and returns its payload.
func (a *Apple) verifyJWS(jws string) ([]byte, error) {
	parts := strings.Split(jws, ".")
	if len(parts) != 3 || a.Roots == nil {
		return nil, ErrInvalid
	}
	var hdr struct {
		Alg string   `json:"alg"`
		X5C []string `json:"x5c"`
	}
	if err := decodeSegment(parts[0], &hdr); err != nil || hdr.Alg != "ES256" || len(hdr.X5C) < 2 {
		return nil, ErrInvalid
	}
	certs := make([]*x509.Certificate, len(hdr.X5C))
	for i, c := range hdr.X5C {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return nil, ErrInvalid
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return nil, ErrInvalid
		}
	}
	if !hasExtension(certs[0], oidAppleLeaf) || !hasExtension(certs[1], oidAppleIntermediate) {
		return nil, ErrInvalid
	}
	inter := x509.NewCertPool()
	for _, c := range certs[1:] {
		inter.AddCert(c)
	}
	now := time.Now
	if a.Now != nil {
		now = a.Now
	}
	if _, err := certs[0].Verify(x509.VerifyOptions{Roots: a.Roots, Intermediates: inter, CurrentTime: now(),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}); err != nil {
		return nil, ErrInvalid
	}
	pub, ok := certs[0].PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return nil, ErrInvalid
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return nil, ErrInvalid
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(pub, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
		return nil, ErrInvalid
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, ErrInvalid
	}
	return payload, nil
}

func decodeSegment(seg string, v any) error {
	b, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

func hasExtension(c *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}
