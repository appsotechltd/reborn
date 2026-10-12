# Deploying Reborn

## Free: Render

[`render.yaml`](../render.yaml) describes everything on Render's free plan, in Frankfurt:

| Service | What it is |
|---|---|
| `reborn-db` | Postgres 16 with pgvector |
| `reborn-redis` | Render Key Value (Redis) for caching and rate limits |
| `reborn-api` | The Go API, built from [`deploy/api.Dockerfile`](../deploy/api.Dockerfile). The card library is baked in and imported on every start |
| `reborn-web` | The Next.js site, built from [`web/Dockerfile`](../web/Dockerfile) |

In the Render dashboard: **New > Blueprint**, pick this repository, paste the four `R2_*`
values (so the API can see which explainer videos are in the bucket), and **Apply**.
`OPENAI_API_KEY` and `ANTHROPIC_API_KEY` can stay empty: Reborn AI and the guide are then off.

Things to know about the free plan:

- Web services sleep after 15 minutes without traffic; the next request wakes them in about a minute.
- The free Postgres expires 30 days after it is created. To keep the data, create a free
  database on Neon or Supabase (both support pgvector) and set `DATABASE_URL` on `reborn-api`
  to its connection string (with `sslmode=require`).
- If a service name is taken, Render adds a suffix to its URL. Then update `WEB_BASE_URL`
  on the API, `NEXT_PUBLIC_API_URL`, `API_URL` and `SITE_URL` on the web service, and
  redeploy `reborn-web` (`NEXT_PUBLIC_API_URL` is baked in at build time).

## Android test APK

The **Android test build** workflow builds a release APK against the hosted API and
publishes it as the `apk-latest` release on GitHub. It runs on every push to `main` that
touches `app/`, or by hand from the Actions tab. Set the repository variables
`API_BASE_URL` and `WEB_BASE_URL` if the hosted URLs differ from the defaults.

## Your own server

On any machine with Docker (for example a VPS), the repo's `docker-compose.yml` runs the
full stack, including Kokoro for Reborn AI's voice:

```sh
cp .env.example .env    # then fill it in
docker compose up -d --build
docker compose run --rm seed
```

Put a reverse proxy with HTTPS (Caddy is the shortest) in front of ports 3000 and 8080, and
build the web image with `NEXT_PUBLIC_API_URL` set to the public API URL.
