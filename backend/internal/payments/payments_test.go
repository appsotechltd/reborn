package payments

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type testCA struct {
	cert *x509.Certificate
	key  *ecdsa.PrivateKey
}

func newCert(t *testing.T, parent *testCA, isCA bool, ext asn1.ObjectIdentifier) *testCA {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(time.Now().UnixNano()),
		Subject:               pkix.Name{CommonName: fmt.Sprintf("test %v", ext)},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  isCA,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
	}
	if ext != nil {
		tmpl.ExtraExtensions = []pkix.Extension{{Id: ext, Value: []byte{5, 0}}}
	}
	signer, signerCert := key, tmpl
	if parent != nil {
		signer, signerCert = parent.key, parent.cert
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, signerCert, &key.PublicKey, signer)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(der)
	return &testCA{cert: cert, key: key}
}

func signJWS(t *testing.T, leaf *testCA, chain []*x509.Certificate, payload any) string {
	t.Helper()
	x5c := make([]string, len(chain))
	for i, c := range chain {
		x5c[i] = base64.StdEncoding.EncodeToString(c.Raw)
	}
	h, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": x5c})
	p, _ := json.Marshal(payload)
	signing := base64.RawURLEncoding.EncodeToString(h) + "." + base64.RawURLEncoding.EncodeToString(p)
	digest := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, leaf.key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func TestAppleVerifyTransaction(t *testing.T) {
	root := newCert(t, nil, true, nil)
	inter := newCert(t, root, true, oidAppleIntermediate)
	leaf := newCert(t, inter, false, oidAppleLeaf)
	pool := x509.NewCertPool()
	pool.AddCert(root.cert)
	a := &Apple{BundleID: "app.reborn", Roots: pool}
	chain := []*x509.Certificate{leaf.cert, inter.cert, root.cert}
	good := map[string]any{"transactionId": "2000001", "bundleId": "app.reborn", "productId": "reborn.gift.sun", "type": "Consumable"}

	tx, err := a.VerifyTransaction(signJWS(t, leaf, chain, good))
	if err != nil || tx.TransactionID != "2000001" || tx.ProductID != "reborn.gift.sun" {
		t.Fatalf("tx = %+v, err = %v", tx, err)
	}

	other := map[string]any{"transactionId": "2000001", "bundleId": "com.someone.else", "productId": "reborn.gift.sun"}
	if _, err := a.VerifyTransaction(signJWS(t, leaf, chain, other)); err == nil {
		t.Fatal("accepted another app's transaction")
	}
	revoked := map[string]any{"transactionId": "2000002", "bundleId": "app.reborn", "productId": "reborn.gift.sun", "revocationDate": 1}
	if _, err := a.VerifyTransaction(signJWS(t, leaf, chain, revoked)); err == nil {
		t.Fatal("accepted a refunded transaction")
	}
	// A chain from a root we don't trust.
	fakeRoot := newCert(t, nil, true, nil)
	fakeInter := newCert(t, fakeRoot, true, oidAppleIntermediate)
	fakeLeaf := newCert(t, fakeInter, false, oidAppleLeaf)
	if _, err := a.VerifyTransaction(signJWS(t, fakeLeaf, []*x509.Certificate{fakeLeaf.cert, fakeInter.cert, fakeRoot.cert}, good)); err == nil {
		t.Fatal("accepted an untrusted chain")
	}
	// A leaf without Apple's marker extension.
	plain := newCert(t, inter, false, nil)
	if _, err := a.VerifyTransaction(signJWS(t, plain, []*x509.Certificate{plain.cert, inter.cert, root.cert}, good)); err == nil {
		t.Fatal("accepted a leaf without Apple's extension")
	}
	// A tampered payload.
	jws := signJWS(t, leaf, chain, good)
	parts := strings.Split(jws, ".")
	evil, _ := json.Marshal(map[string]any{"transactionId": "9", "bundleId": "app.reborn", "productId": "reborn.gift.sun"})
	parts[1] = base64.RawURLEncoding.EncodeToString(evil)
	if _, err := a.VerifyTransaction(strings.Join(parts, ".")); err == nil {
		t.Fatal("accepted a tampered payload")
	}
}

func TestGoogleVerifyPurchase(t *testing.T) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/token":
			_ = r.ParseForm()
			if r.Form.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || r.Form.Get("assertion") == "" {
				http.Error(w, "bad grant", 400)
				return
			}
			fmt.Fprint(w, `{"access_token":"ya29.test"}`)
		case r.Header.Get("Authorization") != "Bearer ya29.test":
			http.Error(w, "no auth", 401)
		case strings.HasSuffix(r.URL.Path, "/purchases/products/reborn.gift.spark/tokens/good"):
			fmt.Fprint(w, `{"orderId":"GPA.1234","purchaseState":0}`)
		case strings.HasSuffix(r.URL.Path, "/tokens/pending"):
			fmt.Fprint(w, `{"orderId":"GPA.5678","purchaseState":2}`)
		default:
			http.Error(w, "not found", 404)
		}
	}))
	defer srv.Close()
	sa, _ := json.Marshal(map[string]string{"client_email": "svc@test.iam", "private_key": string(keyPEM), "token_uri": srv.URL + "/token"})
	g := &Google{PackageName: "app.reborn", ServiceAccount: sa, BaseURL: srv.URL}
	ctx := context.Background()

	p, err := g.VerifyPurchase(ctx, "reborn.gift.spark", "good")
	if err != nil || p.OrderID != "GPA.1234" {
		t.Fatalf("purchase = %+v, err = %v", p, err)
	}
	if _, err := g.VerifyPurchase(ctx, "reborn.gift.spark", "pending"); err != ErrInvalid {
		t.Fatalf("pending purchase err = %v", err)
	}
	if _, err := g.VerifyPurchase(ctx, "reborn.gift.spark", "unknown"); err != ErrInvalid {
		t.Fatalf("unknown token err = %v", err)
	}
}

func TestStripeWebhookTimestamp(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := &Stripe{WebhookSecret: "whsec", Now: func() time.Time { return now }}
	if _, err := s.VerifyWebhook([]byte(`{}`), "t=1700000000,v1=00"); err != ErrInvalid {
		t.Fatalf("old webhook err = %v", err)
	}
	if _, err := s.VerifyWebhook([]byte(`{}`), ""); err != ErrInvalid {
		t.Fatalf("unsigned webhook err = %v", err)
	}
}

func TestTiers(t *testing.T) {
	for _, tr := range Tiers {
		if got, ok := TierByProduct(tr.ProductID); !ok || got.ID != tr.ID {
			t.Fatalf("tier %s", tr.ID)
		}
	}
	if _, ok := TierByID("nope"); ok {
		t.Fatal("unknown tier found")
	}
}
