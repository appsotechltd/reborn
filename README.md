# Reborn

A microlearning app that turns the best ideas from books and other long-form content into
short, practical **idea cards** you can read in about a minute. Discover ideas, stash them
into collections, review them so they stick, and apply them to your work, mind, health and
relationships.

| Folder | What's in it |
|---|---|
| [`app/`](app) | Flutter + Riverpod mobile app for Android and iOS |
| [`web/`](web) | Next.js web app; public pages for every idea, source and topic are server-rendered for search engines and link previews |
| [`backend/`](backend) | Go API server (Postgres + pgvector, Redis), content importer, AI guide |
| [`content/`](content) | The card library: one JSON file per source, plus the [schema](content/SCHEMA.md) |
| [`content/explainers/`](content/explainers) | Animated explainer videos for cards, their renderer, and the realistic-film pipeline |
| [`docs/API.md`](docs/API.md) | The HTTP API the app talks to |

## Features

- **Idea cards** with title, body, optional quote, an **Apply it** prompt and a credit line naming
  the source and licence on every card. Health cards always carry a "not medical advice" note.
- **Feed** by topic (nine categories), unread cards first, reshuffled daily; a **daily idea**.
- **Search** that combines Postgres full-text search with semantic vector search (pgvector) when
  embeddings are configured.
- **Stashes**: personal collections. Stashing a card enrols it in **spaced-repetition review**,
  and **quizzes** test what you've read.
- **Explainer videos**: short animated films that dramatise a card, with captions and the source
  credit on screen, played on the card in the web and mobile apps.
- **Audio mode** (on-device text-to-speech) and **offline reading** of stashed and recent cards.
- **Contributions** from readers, written in their own words and published only after a
  moderator approves them.
- **Ask Reborn**, an AI guide built on Claude that answers only from the card library and cites
  the cards it used. It is retrieval-augmented rather than fine-tuned, so new cards are usable
  the moment they're imported and every answer links back to its sources.

## Run it locally

You need Docker, Go 1.26+ and Flutter (stable).

```sh
docker compose up -d db redis                      # Postgres with pgvector, and Redis
cd backend
go run ./cmd/reborn seed ../content/library        # import the library (or testdata/library for fixtures)
ANTHROPIC_API_KEY=sk-ant-... go run ./cmd/reborn serve   # API on :8080
```

In other terminals:

```sh
cd web && npm install && npm run dev               # web app on http://localhost:3000
cd app && flutter run                              # mobile app (emulator: API_BASE_URL=http://10.0.2.2:8080)
```

Or run the whole backend in Docker: `docker compose up --build`, then
`docker compose run --rm seed`.

### Configuration

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgres://reborn:reborn@localhost:5432/reborn?sslmode=disable` | Postgres (needs the `vector` extension) |
| `REDIS_URL` | `redis://localhost:6379/0` | Caching and rate limits; the API still runs without it |
| `JWT_SECRET` | `dev-only-change-me` | Signs session tokens. **Set this in production** |
| `ANTHROPIC_API_KEY` | unset | Enables the AI guide (`/v1/agent/chat`) |
| `AGENT_MODEL` | `claude-opus-5-5` | Claude model for the guide |
| `AGENT_HOURLY_LIMIT` | `30` | Questions per user per hour |
| `VOYAGE_API_KEY` | unset | Enables semantic search embeddings (Voyage AI) |
| `VOYAGE_MODEL` | `voyage-3.5` | Embedding model (1024 dimensions) |
| `CONTENT_DIR` | `../content/library` | Default folder for `seed` and `validate` |
| `EXPLAINER_DIR` | `../content/explainers/out` | Rendered explainer videos and their `manifest.json`; served at `/media/explainers/` |
| `MEDIA_BASE_URL` | (empty) | Public URL of the media bucket (Cloudflare R2); explainer URLs become `MEDIA_BASE_URL/explainers/<file>` |
| `CORS_ORIGINS` | `*` | Comma-separated origins allowed to call the API from a browser |

### Backend commands

```sh
go run ./cmd/reborn validate [dir]          # check library files, no database needed
go run ./cmd/reborn seed [dir]              # validate, import and embed
go run ./cmd/reborn embed                   # embed cards missing vectors
go run ./cmd/reborn make-moderator a@b.com  # let a user moderate contributions
go run ./cmd/reborn serve                   # migrate and serve
```

Tests: `go test ./...` runs unit tests; set `TEST_DATABASE_URL` (a Postgres user that can
create databases) and optionally `TEST_REDIS_URL` to run the API integration tests too.

## Content and licensing rules

Every card records its source, link and licence, and the app shows the credit on every card.
Only public-domain, CC BY / CC BY-SA, CC0, Open Government Licence and US-government sources are
quoted; anything else is summarised in our own words with a link back. Non-commercial licences
are rejected by the importer. See [content/SCHEMA.md](content/SCHEMA.md).

This is not legal advice: have the content policy reviewed before launch.
