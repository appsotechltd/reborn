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
	ExplainerDir    string
	MediaBaseURL    string
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
		ExplainerDir:    env("EXPLAINER_DIR", "../content/explainers/out"),
		MediaBaseURL:    os.Getenv("MEDIA_BASE_URL"),
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
