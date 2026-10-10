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

### User

```json
{ "id": "uuid", "email": "a@b.com", "handle": "ada", "display_name": "Ada", "bio": "", "role": "member", "topics": ["psychology"] }
```

`role` is `member` or `moderator`.

`handle` is unique, 3-30 of `a-z 0-9 _`, generated from the display name at sign-up.
`email` is only ever shown to the user themselves.

### Post

Every published card is a post. People react to, favourite, comment on, share and
gift posts; they never write them.

```json
{
  "id": "meditations-marcus-aurelius--01",
  "published_at": "2026-10-10T09:00:00Z",
  "card": Card,
  "stats": { "reactions": { "love": 3, "insightful": 1 }, "comments": 2, "favorites": 5, "shares": 1, "gifts": 0 },
  "viewer": { "reaction": "love" | null, "favorited": true, "seen": false },
  "reason": { "kind": "author", "label": "Marcus Aurelius" }
}
```

- `viewer` is present only when signed in.
- `reason` is present only in the timeline. `kind` is `source` (a book you follow),
  `author`, `favorite` (`label` is the person you follow who favourited it), `topic`
  (`label` is the topic name), or `new` (no topics or follows set).
- Reactions are `like`, `love`, `insightful`, `inspiring` and `helpful`, one per person per post.
- A post is a video post when `card.explainer` is present (added by the explainer videos work).

### Profile

```json
{ "id": "uuid", "handle": "ada", "display_name": "Ada", "bio": "", "followers": 2, "following": 5,
  "favorites": 12, "is_following": false, "is_me": false }
```

### Comment

```json
{ "id": "uuid", "post_id": "card-id", "parent_id": "uuid" | null, "body": "...",
  "author": { "id": "uuid", "handle": "ada", "display_name": "Ada" }, "created_at": "..." }
```

Replies are one level deep: replying to a reply attaches to its top-level comment.

### Gift

```json
{ "id": "uuid", "post_id": "card-id", "tier": "lamp", "amount_cents": 499, "currency": "usd",
  "provider": "stripe" | "apple" | "google", "status": "pending" | "paid" | "refunded",
  "created_at": "...", "paid_at": "..." | null }
```

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
| `GET /v1/sources/{id}` | optional | | `{"source":Source,"cards":[Card],"follow":{"followers","is_following"}}`. `Source` has the fields in content/SCHEMA.md |
| `GET /v1/sitemap` | none | | `{"cards":[{"id","updated_at"}],"sources":[{"id","updated_at"}],"topics":["business",...]}` for building sitemaps |
| `GET /v1/search` | optional | `?q=sleep&topic=health&limit=20` | `{"cards":[Card]}`. `q` may be omitted when `topic` is given, to browse the topic |
| `POST /v1/auth/register` | none | `{"email","password","display_name"}` (password ≥ 8) | `{"token","user":User}` |
| `POST /v1/auth/login` | none | `{"email","password"}` | `{"token","user":User}` |
| `GET /v1/me` | required | | `User` |
| `PATCH /v1/me` | required | `{"display_name"?, "handle"?, "bio"? (≤300), "topics"?}` | `User`. `409 handle_taken` |
| `DELETE /v1/me` | required | | `204`. Deletes the account and everything it owns |
| `POST /v1/auth/forgot` | none | `{"email"}` | `202` whether or not the account exists. Emails a link to `WEB_BASE_URL/reset-password?token=…` that works once, for 1 hour |
| `POST /v1/auth/reset` | none | `{"token","password"}` | `{"token","user":User}` (signs in). `400 invalid_token` when used or expired |
| `GET /v1/timeline` | optional | `?topics=a,b&cursor=&limit=20` | `{"posts":[Post],"next_cursor":"..."|null}`. Posts from the user's topics, followed books and authors, and posts favourited by people they follow (everything when none are set). Unseen first, then newest first. The cursor pins the first page's time, so marking posts seen while scrolling doesn't shift later pages |
| `POST /v1/seen` | required | `{"post_ids":[...]}` (max 100) | `204`. Call as posts scroll into view |
| `GET /v1/posts/{id}` | optional | | `Post` |
| `PUT /v1/posts/{id}/favorite` | required | | `204` |
| `DELETE /v1/posts/{id}/favorite` | required | | `204` |
| `PUT /v1/posts/{id}/reaction` | required | `{"kind":"love"}` | `204`. Replaces any earlier reaction |
| `DELETE /v1/posts/{id}/reaction` | required | | `204` |
| `POST /v1/posts/{id}/share` | optional | `{"channel"}`: `facebook`, `x`, `whatsapp`, `linkedin`, `telegram`, `email`, `instagram`, `copy_link`, `native`, `embed` | `204`. Counts the share |
| `GET /v1/posts/{id}/comments` | none | `?cursor=&limit=50` | `{"comments":[Comment],"next_cursor"}`, oldest first |
| `POST /v1/posts/{id}/comments` | required | `{"body"(1-1000),"parent_id"?}` | `Comment` (201). 20 per hour |
| `DELETE /v1/comments/{id}` | required | | `204`. Your own, or any for moderators |
| `POST /v1/comments/{id}/report` | required | `{"reason"?}` | `204`. Three reports hide a comment until a moderator decides |
| `GET /v1/me/favorites` | required | `?cursor=&limit=20` | `{"posts":[Post],"next_cursor"}`, newest favourite first |
| `GET /v1/me/following` | required | | `{"following":[{"kind","target","label","handle"?}]}` |
| `PUT /v1/follows/{kind}/{target}` | required | `kind` = `user` (target = user id), `source` (source id) or `author` (URL-escaped name) | `{"followers","is_following"}` |
| `DELETE /v1/follows/{kind}/{target}` | required | | `{"followers","is_following"}` |
| `GET /v1/users/{handle}` | optional | | `Profile` |
| `GET /v1/users/{handle}/favorites` | optional | `?cursor=&limit=20` | `{"posts":[Post],"next_cursor"}` |
| `GET /v1/users/{handle}/followers` | none | `?cursor=&limit=50` | `{"users":[{"id","handle","display_name"}],"next_cursor"}` |
| `GET /v1/authors/{name}` | optional | | `{"name","sources":[...],"followers","is_following"}` |
| `GET /v1/gifts/tiers` | none | | `{"tiers":[{"id","name","amount_cents","currency","product_id"}],"providers":{"stripe","apple","google"}}`. A provider is `false` until its keys are set |
| `POST /v1/posts/{id}/gifts/checkout` | required | `{"tier"}` | `{"gift_id","url"}` (201). Send the browser to `url` (Stripe Checkout). It returns to `/ideas/{id}?gift={gift_id}`. `503 gifts_unavailable` without Stripe keys |
| `POST /v1/posts/{id}/gifts/apple` | required | `{"signed_transaction"}` (StoreKit 2 JWS) | `Gift` (201). Verified against Apple's root certificate; a transaction counts once |
| `POST /v1/posts/{id}/gifts/google` | required | `{"product_id","purchase_token"}` | `Gift` (201). Verified with the Play Developer API |
| `GET /v1/gifts/{id}` | required | | `Gift` (your own) |
| `POST /v1/webhooks/stripe` | Stripe signature | | `204`. Marks the gift paid on `checkout.session.completed` |
| `GET /v1/moderation/comments` | moderator | | `{"comments":[Comment + {"status","reports","reasons"}]}` |
| `POST /v1/moderation/comments/{id}/hide` | moderator | | `204`. Clears its reports |
| `POST /v1/moderation/comments/{id}/restore` | moderator | | `204`. Clears its reports |
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

## Gift configuration

Gifts are product ids `reborn.gift.spark` ($1.99), `reborn.gift.lamp` ($4.99) and
`reborn.gift.sun` ($9.99), set up as consumable in-app products in App Store Connect
and the Play Console. Each provider turns on when its settings are present:

- Stripe (web): `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`. Point a webhook for
  `checkout.session.completed` at `/v1/webhooks/stripe`.
- Apple: `APPLE_BUNDLE_ID`, and `APPLE_ROOT_CA_FILE` with Apple Root CA - G3 from
  https://www.apple.com/certificateauthority/AppleRootCA-G3.cer.
- Google: `GOOGLE_PLAY_PACKAGE`, and `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE` with a service
  account key that has access to the app in the Play Console.

Password reset emails use `SMTP_URL` (`smtp://user:pass@host:587`) and `MAIL_FROM`;
without `SMTP_URL` they are written to the server log. Links point at `WEB_BASE_URL`.
