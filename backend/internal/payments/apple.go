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
	TransactionID  string `json:"transactionId"`
	BundleID       string `json:"bundleId"`
	ProductID      string `json:"productId"`
	Type           string `json:"type"`
	Environment    string `json:"environment"`
	RevocationDate int64  `json:"revocationDate"`
}

// VerifyTransaction checks a signedTransactionInfo JWS and returns its payload.
func (a *Apple) VerifyTransaction(jws string) (AppleTransaction, error) {
	var tx AppleTransaction
	parts := strings.Split(jws, ".")
	if len(parts) != 3 || a.Roots == nil {
		return tx, ErrInvalid
	}
	var hdr struct {
		Alg string   `json:"alg"`
		X5C []string `json:"x5c"`
	}
	if err := decodeSegment(parts[0], &hdr); err != nil || hdr.Alg != "ES256" || len(hdr.X5C) < 2 {
		return tx, ErrInvalid
	}
	certs := make([]*x509.Certificate, len(hdr.X5C))
	for i, c := range hdr.X5C {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return tx, ErrInvalid
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return tx, ErrInvalid
		}
	}
	if !hasExtension(certs[0], oidAppleLeaf) || !hasExtension(certs[1], oidAppleIntermediate) {
		return tx, ErrInvalid
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
		return tx, ErrInvalid
	}
	pub, ok := certs[0].PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return tx, ErrInvalid
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return tx, ErrInvalid
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(pub, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
		return tx, ErrInvalid
	}
	if err := decodeSegment(parts[1], &tx); err != nil {
		return tx, ErrInvalid
	}
	if tx.BundleID != a.BundleID || tx.TransactionID == "" || tx.RevocationDate != 0 {
		return tx, ErrInvalid
	}
	return tx, nil
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
