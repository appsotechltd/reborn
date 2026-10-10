# Reborn web

The Reborn website: public, server-rendered pages for every idea card, source and topic
(readable by search engines and link previews), plus signed-in features (stashes, review,
quizzes, the AI guide, contributions, moderation) that run in the browser against the same
Go API (`../backend`, documented in `../docs/API.md`).

Built with Next.js 16 (App Router, React Server Components), TypeScript (strict) and
Tailwind CSS 4. Tests use Vitest + Testing Library.

## Quick start

```bash
cd web
npm install
cp .env.example .env.local   # optional: defaults already point at localhost
npm run dev                  # http://localhost:3000
```

The API must be running (by default at `http://localhost:8080`, see the repository README).

## Environment variables

| Variable | Used by | Default | Notes |
|---|---|---|---|
| `API_URL` | server (RSC pages, sitemap) | `http://localhost:8080` | Read at request time. In Docker this is usually an internal hostname such as `http://api:8080`. |
| `NEXT_PUBLIC_API_URL` | browser (signed-in features, "load more") | `http://localhost:8080` | **Inlined at build time.** Must be reachable from users' browsers and allowed by the API's CORS settings. |
| `SITE_URL` | canonical URLs, Open Graph, JSON-LD, `sitemap.xml`, `robots.txt` | `http://localhost:3000` | Set to the public origin (no trailing slash). Read when pages render; statically built pages pick it up at build time. |

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Development server with hot reload |
| `npm run build` | Production build (`output: "standalone"`) |
| `npm start` | Serve the production build |
| `npm run lint` | ESLint (Next.js core-web-vitals + TypeScript config) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Vitest (jsdom) |

## How it talks to the API

- `lib/api.ts` is the single typed client for every endpoint in `docs/API.md`. Every failure
  becomes an `ApiError` with `status`, `code` and `message` taken from the API's
  `{ "error": { "code", "message" } }` body (or a generic message if the body isn't JSON);
  network failures have `status: 0`, `code: "network_error"`.
- **Public pages** (`/`, `/ideas/[id]`, `/sources`, `/sources/[id]`, `/topics/[slug]`,
  `/search`, `sitemap.xml`) are React Server Components that fetch anonymously from
  `API_URL` via `lib/server-api.ts`. Responses are cached and pages are regenerated at most
  every 10 minutes (ISR, `revalidate = 600`). Card and source pages are prebuilt from
  `GET /v1/sitemap` when the API is reachable at build time; any other id renders on its
  first request and is then cached. Unknown ids return a real 404.
- **Builds without a backend**: if the API is unreachable while building, `loadOr()` in
  `lib/server-api.ts` falls back gracefully and opts the page into dynamic rendering (via
  `connection()`), so `npm run build` succeeds in CI and no outage is baked into static
  output. At runtime, a failed background revalidation keeps serving the last good page.
- **Signed-in features** are client components. `lib/auth.tsx` keeps the token and user from
  register/login in `localStorage` (`reborn.auth`), refreshes the profile from `GET /v1/me`
  and drops the token on 401. Pages wrap their content in `<RequireAuth>`, which shows a
  sign-in prompt to signed-out visitors. Opening a card while signed in records a view
  (`POST /v1/cards/{id}/view`).
- **The AI guide** (`/ask`) sends the full conversation to `POST /v1/agent/chat` and turns
  inline `[card-id]` citations into numbered links to `/ideas/[id]` (`lib/citations.ts`,
  `components/CitedText.tsx`). `503 agent_unavailable` (no Anthropic key on the server, the
  default locally) and `429` show friendly states and keep the question for a retry.

- **The social layer**: every published card is a post. The home page is the timeline
  (`GET /v1/timeline`): the anonymous first page is server-rendered, then signed-in readers
  get their own, with infinite scroll, a "why you're seeing this" line, posts marked seen
  after about a second at least half on screen (batched to `POST /v1/seen`) and a "You're
  all caught up" divider. `components/PostActions.tsx` holds reactions, favourite, comment
  count, share, embed and gift, all optimistic; signed-out taps go to sign in.
- **Sharing and embeds**: share links point at the canonical `/ideas/[id]` page.
  `/embed/ideas/[id]` renders the card without site chrome and is the only path that may be
  framed (`frame-ancestors *`; everything else sends `X-Frame-Options: SAMEORIGIN` and
  `frame-ancestors 'self'`, see `next.config.ts`). `/oembed?url=…&format=json` is an oEmbed
  provider, advertised on idea pages, which also get a generated Open Graph image.

- **Engagement**: a header bell polls the unread count (`GET /v1/notifications?limit=1`, every
  minute and on focus); `/notifications` marks items read on open or all at once and links each
  to its comment (`/ideas/[id]#comment-…`), post, circle or profile. Signed-in readers see a
  streak widget above the timeline (`GET /v1/me/streak`). Settings holds the daily goal,
  timezone (defaults to the browser's), push toggles and the "Blocked & muted" list; a "⋯"
  menu on profiles and comment authors mutes or blocks. Sign-up sends the browser's
  `timezone` and any `referral_code` (from `/register?ref=`, or remembered by
  `/join?ref=CODE` in `localStorage` under `reborn.referral`). Web push is not implemented.
- **Discover and circles**: `/discover` (server-rendered) has trending posts with a topic
  filter, new posts, popular books and authors, and circles. `/circles` lists yours and
  browses by book; source pages have a Circles section with a create form; `/circles/[id]`
  shows the thread to members, polling every 10 seconds while the tab is visible, with ideas
  from the book attachable to messages. Public stashes appear on profiles and at `/s/[id]`
  (server-rendered with Open Graph tags, revalidated every minute).
- **Premium, referrals, dashboard**: `/premium` shows plans and status, starts Stripe
  Checkout, thanks on `?welcome=1`, opens the billing portal, and says "coming soon" when
  `providers.stripe` is false. `/invite` has the invite link and counts. `/admin`
  (moderators) shows stat tiles, a 30-day inline-SVG chart, retention, engagement, revenue,
  top posts and links to the moderation queues.

Caching uses Next's classic ISR model rather than Cache Components, so the first visit to a
card that wasn't prebuilt waits for the real content (good for crawlers and link previews)
instead of streaming a fallback shell.

## Credit and licences

Every card view shows the `credit` line (linked to the source page), a link to the original
and its licence, and the health `disclaimer` whenever the API sends one. Keep it that way:
`tests/card-view.test.tsx` checks it.

## Layout

```
app/                 routes (public pages are server components; signed-in pages render a client view)
  page.tsx           home timeline
  ideas/[id]/        idea card page (JSON-LD Article, quiz, listen, stash, post actions, comments,
                     opengraph-image / twitter-image)
  embed/ideas/[id]/, oembed/   embeddable card and oEmbed endpoint
  sources/, sources/[id]/, authors/[name]/, topics/[slug]/, search/, u/[handle]/, discover/,
  s/[id]/ (public stash), circles/, circles/[id]/
  signin/, register/, join/, forgot-password/, reset-password/, stashes/, stashes/[id]/, review/,
  quiz/, ask/, contribute/, moderation/, settings/, favorites/, following/, notifications/,
  premium/, invite/, admin/
  sitemap.ts, robots.ts, layout.tsx, not-found.tsx, error.tsx
components/          CardView, PostCard, PostActions, Timeline, Comments, ShareMenu, GiftButton, FollowButton, …
lib/                 api client, server data loaders, auth context, types, helpers
tests/               Vitest tests
```

## Docker

```bash
docker build -t reborn-web \
  --build-arg NEXT_PUBLIC_API_URL=https://api.example.com \
  --build-arg SITE_URL=https://reborn.example.com .
docker run -p 3000:3000 -e API_URL=http://api:8080 -e SITE_URL=https://reborn.example.com reborn-web
```

The image runs the standalone server (`node server.js`) as a non-root user.
