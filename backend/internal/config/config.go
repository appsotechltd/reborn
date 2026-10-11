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
	OpenAIAPIKey    string // Reborn AI; also used by the content pipeline's image generation
	AIChatModel     string
	AIEffort        string // reasoning effort for AIChatModel; "none" for a non-reasoning model
	AIVoice         string
	KokoroURL       string // Reborn's Kokoro speech service; when set, replies are read aloud with it for free
	KokoroVoice     string
	AIMonthlyUnits  int
	AIHourly        int
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

	// Media files live in Cloudflare R2 when the R2 keys are set, else on local disk.
	R2AccountID  string
	R2AccessKey  string
	R2SecretKey  string
	R2Bucket     string
	MediaBaseURL string // public URL of the bucket (custom domain or r2.dev); "/media" locally
	MediaDir     string // local fallback folder for development
	ExplainerDir string // folder holding the explainers' manifest.json
	CardAudioDir string // folder holding the card recordings' manifest.json
}

// R2Enabled reports whether every R2 setting is present.
func (c Config) R2Enabled() bool {
	return c.R2AccountID != "" && c.R2AccessKey != "" && c.R2SecretKey != "" && c.R2Bucket != ""
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
		OpenAIAPIKey:    os.Getenv("OPENAI_API_KEY"),
		AIChatModel:     env("OPENAI_CHAT_MODEL", "gpt-5.4-mini"),
		AIEffort:        env("OPENAI_REASONING_EFFORT", "low"),
		AIVoice:         env("OPENAI_TTS_VOICE", "marin"),
		KokoroURL:       os.Getenv("KOKORO_URL"),
		KokoroVoice:     env("KOKORO_VOICE", "af_heart"),
		AIMonthlyUnits:  envInt("AI_MONTHLY_UNITS", 250),
		AIHourly:        envInt("AI_HOURLY_LIMIT", 60),
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

		R2AccountID:  os.Getenv("R2_ACCOUNT_ID"),
		R2AccessKey:  os.Getenv("R2_ACCESS_KEY_ID"),
		R2SecretKey:  os.Getenv("R2_SECRET_ACCESS_KEY"),
		R2Bucket:     os.Getenv("R2_BUCKET"),
		MediaBaseURL: os.Getenv("MEDIA_BASE_URL"),
		MediaDir:     env("MEDIA_DIR", "media"),
		ExplainerDir: env("EXPLAINER_DIR", "../content/explainers/out"),
		CardAudioDir: env("CARD_AUDIO_DIR", "../content/audio/out"),
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
