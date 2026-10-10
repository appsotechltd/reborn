// Command reborn runs the Reborn API server and its maintenance tasks.
//
//	reborn serve                  run migrations and serve the API
//	reborn migrate                apply database migrations
//	reborn validate [dir]         check library files without a database
//	reborn seed [dir]             validate and import library files, then embed
//	reborn embed                  embed cards that lack vectors (needs VOYAGE_API_KEY)
//	reborn make-moderator <email> give a user the moderator role
package main

import (
	"context"
	"crypto/x509"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/appsotechltd/reborn/backend/internal/agent"
	"github.com/appsotechltd/reborn/backend/internal/api"
	"github.com/appsotechltd/reborn/backend/internal/auth"
	"github.com/appsotechltd/reborn/backend/internal/cache"
	"github.com/appsotechltd/reborn/backend/internal/config"
	"github.com/appsotechltd/reborn/backend/internal/content"
	"github.com/appsotechltd/reborn/backend/internal/db"
	"github.com/appsotechltd/reborn/backend/internal/embed"
	"github.com/appsotechltd/reborn/backend/internal/mail"
	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, nil)))
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: reborn serve|migrate|validate|seed|embed|make-moderator")
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	cfg := config.Load()
	if err := run(ctx, cfg, os.Args[1], os.Args[2:]); err != nil {
		slog.Error(os.Args[1]+" failed", "err", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, cfg config.Config, cmd string, args []string) error {
	if cmd == "validate" {
		_, err := loadLibrary(dirArg(cfg, args))
		return err
	}
	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect to postgres: %w", err)
	}
	defer pool.Close()
	n, err := db.Migrate(ctx, pool)
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	if n > 0 {
		slog.Info("applied migrations", "count", n)
	}
	st := store.New(pool)
	if err := st.EnsureTopics(ctx); err != nil {
		return err
	}
	embedder := embed.NewVoyage(cfg.VoyageAPIKey, cfg.VoyageModel)

	switch cmd {
	case "migrate":
		return nil
	case "seed":
		lib, err := loadLibrary(dirArg(cfg, args))
		if err != nil {
			return err
		}
		res, err := st.Seed(ctx, lib)
		if err != nil {
			return err
		}
		slog.Info("seeded", "sources", res.Sources, "cards", res.Cards, "changed", res.Changed)
		return embedAll(ctx, st, embedder)
	case "embed":
		if embedder == nil {
			return errors.New("VOYAGE_API_KEY is not set")
		}
		return embedAll(ctx, st, embedder)
	case "make-moderator":
		if len(args) != 1 {
			return errors.New("usage: reborn make-moderator <email>")
		}
		return st.SetRole(ctx, args[0], "moderator")
	case "serve":
		return serve(ctx, cfg, st, embedder)
	default:
		return fmt.Errorf("unknown command %q", cmd)
	}
}

func dirArg(cfg config.Config, args []string) string {
	if len(args) > 0 {
		return args[0]
	}
	return cfg.ContentDir
}

func loadLibrary(dir string) (content.Library, error) {
	lib, problems, err := content.LoadDir(dir)
	if err != nil {
		return lib, err
	}
	errs := 0
	for _, p := range problems {
		fmt.Fprintln(os.Stderr, p.String())
		if !p.Warning {
			errs++
		}
	}
	cards := 0
	for _, f := range lib.Files {
		cards += len(f.Cards)
	}
	slog.Info("library loaded", "dir", dir, "sources", len(lib.Files), "cards", cards, "errors", errs)
	if errs > 0 {
		return lib, fmt.Errorf("%d validation errors", errs)
	}
	return lib, nil
}

func embedAll(ctx context.Context, st *store.Store, e embed.Embedder) error {
	if e == nil {
		slog.Info("skipping embeddings: VOYAGE_API_KEY is not set (search uses keywords only)")
		return nil
	}
	n, err := st.EmbedMissing(ctx, e)
	slog.Info("embedded cards", "count", n)
	return err
}

func serve(ctx context.Context, cfg config.Config, st *store.Store, e embed.Embedder) error {
	c, err := cache.Open(ctx, cfg.RedisURL)
	if err != nil {
		slog.Warn("redis unavailable; running without cache and rate limits", "err", err)
		c = nil
	}
	if cfg.JWTSecret == "dev-only-change-me" {
		slog.Warn("JWT_SECRET is the development default; set it in production")
	}
	srv := &api.Server{
		Store:       st,
		Cache:       c,
		Tokens:      auth.NewTokens(cfg.JWTSecret),
		Embedder:    e,
		AgentHourly: cfg.AgentHourly,
		CORSOrigins: cfg.CORSOrigins,
		WebBaseURL:  strings.TrimRight(cfg.WebBaseURL, "/"),
	}
	if srv.Mailer, err = mail.FromURL(cfg.SMTPURL, cfg.MailFrom); err != nil {
		return err
	}
	if cfg.SMTPURL == "" {
		slog.Warn("SMTP_URL is not set; password reset emails are written to the log")
	}
	if err := setupPayments(cfg, srv); err != nil {
		return err
	}
	if cfg.AnthropicAPIKey != "" {
		srv.Agent = agent.New(cfg.AnthropicAPIKey, cfg.AgentModel, st, e)
	} else {
		slog.Warn("ANTHROPIC_API_KEY is not set; the AI guide is disabled")
	}
	hs := &http.Server{Addr: cfg.Addr, Handler: srv.Handler(), ReadHeaderTimeout: 10 * time.Second}
	errc := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", cfg.Addr)
		errc <- hs.ListenAndServe()
	}()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return hs.Shutdown(shutdown)
	}
}

// setupPayments turns on each gift provider whose keys are configured.
func setupPayments(cfg config.Config, srv *api.Server) error {
	if cfg.StripeSecretKey != "" && cfg.StripeWebhookSecret != "" {
		srv.Stripe = &payments.Stripe{SecretKey: cfg.StripeSecretKey, WebhookSecret: cfg.StripeWebhookSecret}
	}
	if cfg.AppleBundleID != "" && cfg.AppleRootCAFile != "" {
		raw, err := os.ReadFile(cfg.AppleRootCAFile)
		if err != nil {
			return fmt.Errorf("APPLE_ROOT_CA_FILE: %w", err)
		}
		pool := x509.NewCertPool()
		if !pool.AppendCertsFromPEM(raw) {
			cert, err := x509.ParseCertificate(raw)
			if err != nil {
				return fmt.Errorf("APPLE_ROOT_CA_FILE: not a PEM or DER certificate")
			}
			pool.AddCert(cert)
		}
		srv.Apple = &payments.Apple{BundleID: cfg.AppleBundleID, Roots: pool}
	}
	if cfg.GooglePackageName != "" && cfg.GoogleServiceFile != "" {
		key, err := os.ReadFile(cfg.GoogleServiceFile)
		if err != nil {
			return fmt.Errorf("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE: %w", err)
		}
		srv.Google = &payments.Google{PackageName: cfg.GooglePackageName, ServiceAccount: key}
	}
	slog.Info("gift providers", "stripe", srv.Stripe != nil, "apple", srv.Apple != nil, "google", srv.Google != nil)
	return nil
}
