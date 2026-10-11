// Command reborn runs the Reborn API server and its maintenance tasks.
//
//	reborn serve                  run migrations and serve the API
//	reborn migrate                apply database migrations
//	reborn validate [dir]         check library files without a database
//	reborn seed [dir]             validate and import library files, then embed
//	reborn embed                  embed cards that lack vectors (needs VOYAGE_API_KEY)
//	reborn make-moderator <email> give a user the moderator role
//	reborn media-upload <dir> [prefix]
//	                              copy media files to R2 (or MEDIA_DIR), skipping unchanged ones
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
	"github.com/appsotechltd/reborn/backend/internal/explainers"
	"github.com/appsotechltd/reborn/backend/internal/mail"
	"github.com/appsotechltd/reborn/backend/internal/objstore"
	"github.com/appsotechltd/reborn/backend/internal/payments"
	"github.com/appsotechltd/reborn/backend/internal/push"
	"github.com/appsotechltd/reborn/backend/internal/rebornai"
	"github.com/appsotechltd/reborn/backend/internal/store"
)

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, nil)))
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: reborn serve|migrate|validate|seed|embed|make-moderator|media-upload")
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
	if cmd == "media-upload" {
		return mediaUpload(ctx, cfg, args)
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
	media := mediaStore(cfg)
	set, err := explainers.Load(ctx, cfg.ExplainerDir, media)
	if err != nil {
		return fmt.Errorf("load explainers: %w", err)
	}
	store.SetExplainers(set)
	slog.Info("explainer videos", "cards", len(set), "manifest", cfg.ExplainerDir)
	srv := &api.Server{
		Store:          st,
		Cache:          c,
		Tokens:         auth.NewTokens(cfg.JWTSecret),
		Embedder:       e,
		AgentHourly:    cfg.AgentHourly,
		CORSOrigins:    cfg.CORSOrigins,
		AIMonthlyUnits: cfg.AIMonthlyUnits,
		AIHourly:       cfg.AIHourly,
		WebBaseURL:     strings.TrimRight(cfg.WebBaseURL, "/"),
		Media:          media,
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
	if cfg.OpenAIAPIKey != "" {
		models := rebornai.DefaultModels
		models.Chat, models.Effort, models.Voice = cfg.AIChatModel, cfg.AIEffort, cfg.AIVoice
		if models.Effort == "none" {
			models.Effort = ""
		}
		srv.AI = &rebornai.Assistant{AI: &rebornai.OpenAI{APIKey: cfg.OpenAIAPIKey}, Lib: st, Embedder: e, Media: media, Models: models}
	} else {
		slog.Warn("OPENAI_API_KEY is not set; Reborn AI is disabled")
	}
	go srv.RunDailyPushes(ctx, 5*time.Minute)
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

// setupPayments turns on each payment provider, and push, whose keys are configured.
func setupPayments(cfg config.Config, srv *api.Server) error {
	if cfg.StripeSecretKey != "" && cfg.StripeWebhookSecret != "" {
		srv.Stripe = &payments.Stripe{SecretKey: cfg.StripeSecretKey, WebhookSecret: cfg.StripeWebhookSecret}
		srv.StripePrices = map[string]string{}
		if cfg.StripePriceMonthly != "" {
			srv.StripePrices["monthly"] = cfg.StripePriceMonthly
		}
		if cfg.StripePriceYearly != "" {
			srv.StripePrices["yearly"] = cfg.StripePriceYearly
		}
	}
	srv.GoogleRTDNToken = cfg.GoogleRTDNToken
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
	if cfg.FirebaseServiceFile != "" {
		key, err := os.ReadFile(cfg.FirebaseServiceFile)
		if err != nil {
			return fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_FILE: %w", err)
		}
		if srv.Push, err = push.NewFCM(key); err != nil {
			return fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_FILE: %w", err)
		}
	}
	slog.Info("payment and push providers", "stripe", srv.Stripe != nil, "apple", srv.Apple != nil, "google", srv.Google != nil, "push", srv.Push != nil)
	return nil
}

// mediaStore is R2 when its keys are set, else the local MEDIA_DIR served at /media.
func mediaStore(cfg config.Config) objstore.Store {
	if cfg.R2Enabled() {
		if cfg.MediaBaseURL == "" {
			slog.Warn("MEDIA_BASE_URL is not set; media links will not resolve until the bucket has a public URL")
		}
		slog.Info("media storage", "backend", "r2", "bucket", cfg.R2Bucket, "public_url", cfg.MediaBaseURL)
		return objstore.NewR2(cfg.R2AccountID, cfg.R2Bucket, cfg.R2AccessKey, cfg.R2SecretKey, cfg.MediaBaseURL)
	}
	base := cfg.MediaBaseURL
	if base == "" {
		// Apps need absolute links; in development the API serves the files itself.
		host := cfg.Addr
		if strings.HasPrefix(host, ":") {
			host = "localhost" + host
		}
		base = "http://" + host + "/media"
	}
	slog.Warn("R2 is not configured; media files are kept on local disk (development only)", "dir", cfg.MediaDir)
	return &objstore.Local{Dir: cfg.MediaDir, BaseURL: base}
}

func mediaUpload(ctx context.Context, cfg config.Config, args []string) error {
	if len(args) < 1 || len(args) > 2 {
		return errors.New("usage: reborn media-upload <dir> [prefix]")
	}
	prefix := ""
	if len(args) == 2 {
		prefix = args[1]
	}
	st := mediaStore(cfg)
	res, err := objstore.UploadDir(ctx, st, args[0], prefix, func(key string) { slog.Info("uploaded", "key", key, "url", st.URL(key)) })
	slog.Info("media upload", "uploaded", res.Uploaded, "unchanged", res.Unchanged, "skipped", res.Skipped)
	return err
}
