# Reborn API (v1)

Base URL: `http://localhost:8080` in development. All bodies are JSON. Authenticated
endpoints take `Authorization: Bearer <token>` (the token from register/login).
Endpoints marked *optional auth* work signed out and personalise when signed in.

Errors always look like:

```json
{ "error": { "code": "not_found", "message": "card not found" } }
```

## Objects

### Card

```json
{
  "id": "meditations-marcus-aurelius--01",
  "title": "Expect difficult people before the day starts",
  "body": "Each morning, Marcus reminded himself...",
  "quote": "Begin the morning by saying to thyself...",
  "apply_it": "Before your next meeting, name one way it could go badly...",
  "topic": "mindfulness",
  "tags": ["stoicism"],
  "locator": "Book II, 1",
  "health": false,
  "disclaimer": null,
  "quiz": { "question": "...", "options": ["...", "..."], "answer": 1, "explanation": "..." },
  "source": {
    "id": "meditations-marcus-aurelius",
    "title": "Meditations",
    "authors": ["Marcus Aurelius"],
    "kind": "book",
    "url": "https://www.gutenberg.org/ebooks/2680",
    "licence": "public-domain",
    "licence_url": "https://www.gutenberg.org/policy/license.html",
    "attribution": "Marcus Aurelius, Meditations (trans. George Long), Project Gutenberg, public domain"
  },
  "credit": "Source: Marcus Aurelius, Meditations (trans. George Long), Project Gutenberg, public domain"
}
```

`quote`, `locator`, `quiz` may be absent/null. `disclaimer` is a string when `health` is true.
Clients must always show `credit`, and `disclaimer` when present.

Cards with a rendered explainer video also carry `explainer` (absent otherwise):

```json
"explainer": {
  "kind": "animated",
  "video_url": "/media/explainers/aesops-fables--07.mp4",
  "poster_url": "/media/explainers/aesops-fables--07.jpg",
  "captions_url": "/media/explainers/aesops-fables--07.vtt",
  "duration_s": 52.3, "width": 720, "height": 1280, "narrated": false
}
```

URLs starting with `/` are relative to the API base URL (the API serves them under
`GET /media/explainers/{file}`, with range requests); with `MEDIA_BASE_URL` set they are absolute (`MEDIA_BASE_URL/explainers/<file>`).
Videos burn in their captions, credit and (for health cards) the health note, so they can play muted.
The web player loads them with `crossorigin="anonymous"` (needed for the captions track), so the
web origin must be in `CORS_ORIGINS`, as it already is for API calls.
`kind` is `animated` today and `film` for realistic films later. See `content/explainers/README.md`.

### User

```json
{ "id": "uuid", "email": "a@b.com", "display_name": "Ada", "role": "member", "topics": ["psychology"] }
```

`role` is `member` or `moderator`.

### Stash

```json
{ "id": "uuid", "name": "Morning reads", "description": "", "card_count": 3, "created_at": "2026-10-10T12:00:00Z" }
```

### Contribution

```json
{
  "id": "uuid", "status": "pending",
  "source": { "title": "Deep Work", "authors": ["Cal Newport"], "url": "https://...", "kind": "book" },
  "topic": "productivity", "title": "...", "body": "...", "apply_it": "...",
  "tags": [], "quiz": null, "moderator_note": null, "card_id": null,
  "created_at": "2026-10-10T12:00:00Z"
}
```

`status` is `pending`, `approved` or `rejected`. `card_id` is set once approved.

## Endpoints

| Method & path | Auth | Body / query | Response |
|---|---|---|---|
| `GET /healthz` | none | | `{"status":"ok"}` |
| `GET /v1/topics` | none | | `{"topics":[{"slug","name","card_count"}]}` |
| `GET /v1/feed` | optional | `?topics=a,b&cursor=&limit=20` | `{"cards":[Card],"next_cursor":"..."|null}`. Without `topics`, uses the signed-in user's topics, else all. Unseen cards first, shuffled daily |
| `GET /v1/daily` | optional | | `{"date":"2026-10-10","card":Card}` |
| `GET /v1/cards/{id}` | none | | `Card` |
| `GET /v1/cards` | none | `?ids=a,b,c` (max 100) | `{"cards":[Card]}` |
| `POST /v1/cards/{id}/view` | required | | `204` (records reading, used by the feed) |
| `GET /v1/sources` | none | `?topic=&cursor=&limit=50` | `{"sources":[{"id","title","authors","kind","licence","attribution","topics":[...],"card_count","updated_at"}],"next_cursor":"..."|null}`, ordered by title. Only sources with published cards |
| `GET /v1/sources/{id}` | none | | `{"source":Source,"cards":[Card]}`. `Source` has the fields in content/SCHEMA.md |
| `GET /v1/sitemap` | none | | `{"cards":[{"id","updated_at"}],"sources":[{"id","updated_at"}],"topics":["business",...]}` for building sitemaps |
| `GET /v1/search` | optional | `?q=sleep&topic=health&limit=20` | `{"cards":[Card]}`. `q` may be omitted when `topic` is given, to browse the topic |
| `POST /v1/auth/register` | none | `{"email","password","display_name"}` (password ≥ 8) | `{"token","user":User}` |
| `POST /v1/auth/login` | none | `{"email","password"}` | `{"token","user":User}` |
| `GET /v1/me` | required | | `User` |
| `PATCH /v1/me` | required | `{"display_name"?, "topics"?}` | `User` |
| `GET /v1/stashes` | required | | `{"stashes":[Stash]}` |
| `POST /v1/stashes` | required | `{"name","description"?}` | `Stash` (201) |
| `GET /v1/stashes/{id}` | required | | `{"stash":Stash,"cards":[Card]}` |
| `PATCH /v1/stashes/{id}` | required | `{"name"?,"description"?}` | `Stash` |
| `DELETE /v1/stashes/{id}` | required | | `204` |
| `PUT /v1/stashes/{id}/cards/{cardId}` | required | | `204`. Also adds the card to review |
| `DELETE /v1/stashes/{id}/cards/{cardId}` | required | | `204` |
| `GET /v1/review/due` | required | `?limit=20` | `{"items":[{"card":Card,"due_at","reps","interval_days"}],"due_count":n}` |
| `POST /v1/review/{cardId}` | required | `{"grade":"again"|"hard"|"good"|"easy"}` | `{"due_at","interval_days","reps"}` |
| `GET /v1/quiz` | required | `?topic=&limit=5` | `{"cards":[Card]}` (all have `quiz`; prefers the user's stashed cards) |
| `POST /v1/contributions` | required | `{"source":{"title","authors","url","kind"},"topic","title","body","apply_it","tags"?,"quiz"?}` | `Contribution` (201) |
| `GET /v1/contributions/mine` | required | | `{"contributions":[Contribution]}` |
| `GET /v1/moderation/queue` | moderator | | `{"contributions":[Contribution]}` |
| `POST /v1/moderation/{id}/approve` | moderator | `{"note"?}` | `Contribution` |
| `POST /v1/moderation/{id}/reject` | moderator | `{"note"}` | `Contribution` |
| `POST /v1/agent/chat` | required | `{"messages":[{"role":"user"|"assistant","content":"..."}]}` (last is `user`) | `{"reply":"...","citations":[Card]}` |

The agent answers only from the card library and cites cards inline as `[card-id]`;
`citations` holds the full cards it cited, in order of first mention. It returns `503`
`agent_unavailable` when the server has no Anthropic API key, and `429` when the user's
hourly limit is hit.
