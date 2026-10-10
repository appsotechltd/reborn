// Package config reads server settings from the environment.
package config

import (
	"os"
	"strconv"
)

// Config holds every setting the server and CLI need.
type Config struct {
	Addr            string
	DatabaseURL     string
	RedisURL        string
	JWTSecret       string
	ContentDir      string
	AnthropicAPIKey string
	AgentModel      string
	AgentHourly     int
	VoyageAPIKey    string
	VoyageModel     string
	CORSOrigins     string

	WebBaseURL string // where reset links and gift return pages point
	SMTPURL    string
	MailFrom   string

	StripeSecretKey     string
	StripeWebhookSecret string
	AppleBundleID       string
	AppleRootCAFile     string // Apple Root CA - G3, DER or PEM
	GooglePackageName   string
	GoogleServiceFile   string // Play Console service account JSON key
	GoogleRTDNToken     string // secret in the Play notifications push URL
	StripePriceMonthly  string
	StripePriceYearly   string
	FirebaseServiceFile string // service account key for push notifications
}

// Load reads the environment, applying development defaults.
func Load() Config {
	return Config{
		Addr:            env("ADDR", ":8080"),
		DatabaseURL:     env("DATABASE_URL", "postgres://reborn:reborn@localhost:5432/reborn?sslmode=disable"),
		RedisURL:        env("REDIS_URL", "redis://localhost:6379/0"),
		JWTSecret:       env("JWT_SECRET", "dev-only-change-me"),
		ContentDir:      env("CONTENT_DIR", "../content/library"),
		AnthropicAPIKey: os.Getenv("ANTHROPIC_API_KEY"),
		AgentModel:      env("AGENT_MODEL", "claude-opus-5-5"),
		AgentHourly:     envInt("AGENT_HOURLY_LIMIT", 30),
		VoyageAPIKey:    os.Getenv("VOYAGE_API_KEY"),
		VoyageModel:     env("VOYAGE_MODEL", "voyage-3.5"),
		CORSOrigins:     env("CORS_ORIGINS", "*"),

		WebBaseURL: env("WEB_BASE_URL", "http://localhost:3000"),
		SMTPURL:    os.Getenv("SMTP_URL"),
		MailFrom:   env("MAIL_FROM", "Reborn <no-reply@reborn.app>"),

		StripeSecretKey:     os.Getenv("STRIPE_SECRET_KEY"),
		StripeWebhookSecret: os.Getenv("STRIPE_WEBHOOK_SECRET"),
		AppleBundleID:       os.Getenv("APPLE_BUNDLE_ID"),
		AppleRootCAFile:     os.Getenv("APPLE_ROOT_CA_FILE"),
		GooglePackageName:   os.Getenv("GOOGLE_PLAY_PACKAGE"),
		GoogleServiceFile:   os.Getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE"),
		GoogleRTDNToken:     os.Getenv("GOOGLE_RTDN_TOKEN"),
		StripePriceMonthly:  os.Getenv("STRIPE_PRICE_MONTHLY"),
		StripePriceYearly:   os.Getenv("STRIPE_PRICE_YEARLY"),
		FirebaseServiceFile: os.Getenv("FIREBASE_SERVICE_ACCOUNT_FILE"),
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return def
}
