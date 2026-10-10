# Explainer videos

Short vertical videos (9:16, about a minute) that dramatise an idea card. The API attaches
each video to its card as `explainer` (see `docs/API.md`), and the web and mobile card views
play it above the card text.

Two kinds:

- **Animated explainers** (`kind: "animated"`), rendered here from original illustrated scenes.
  Five are rendered in `out/`.
- **Realistic films** (`kind: "film"`), shot by a text-to-video model from a reviewed plan.
  The pipeline is ready but unused until a Veo or Runway key is set.

Every video credits its source on screen the whole time, ends on a card with the full credit
and licence, and health cards keep "General information, not medical advice" on screen plus
the full disclaimer at the end. Illustrations are drawn from scratch: no book covers or
copyrighted imagery.

## Setup

Needs Node 22+, ffmpeg (with libx264 and libass), and Chromium.

```sh
cd content/explainers
npm install
npx playwright-core install chromium   # or set CHROMIUM_PATH to an existing Chromium
```

## Animated explainers

Each card with a video has a script in `scripts/<card-id>.json`: a list of scenes, each with
an optional voice-over line. Card text, credit, licence and the health note come from
`content/library`, so they always match the card.

```json
{ "card_id": "aesops-fables--07",
  "scenes": [
    { "type": "title", "narration": "Steady daily effort beats bursts of talent..." },
    { "type": "race", "params": { "hare": { "from": 0.04, "to": 0.58, "state": "run" } }, "narration": "..." },
    { "type": "quote", "narration": "Slow and steady wins the race." },
    { "type": "apply", "narration": "..." },
    { "type": "end", "min_seconds": 4 } ] }
```

```sh
npm run stills -- aesops-fables--07   # a few PNG frames per scene in .cache/stills (seconds)
npm run render -- aesops-fables--07   # out/<id>.mp4 + .jpg poster + .vtt captions, updates out/manifest.json
npm run render                        # every script
npm test
```

A scene lasts as long as its line takes to say (or `min_seconds`). Scenes crossfade; set
`"cut": true` on a scene that continues the previous one exactly. Scene types live in
`renderer/scenes.js`:

| Type | Shows | Params |
|---|---|---|
| `title` | Topic, card title, source | `eyebrow` |
| `statement` | Kinetic lines of text | `lines`, `emphasis` (indexes), `strike` (index), `strikeAt`, `kicker`, `size` |
| `quote` | The card's quote (or `text`), word by word | `text`, `by` |
| `apply` | The card's "Apply it" | `text` |
| `end` | Full credit, licence, health disclaimer | none |
| `race` | The Hare and the Tortoise | `hare {from,to,state: idle/run/sleep/wake, wakeAt}`, `tortoise {from,to}`, `label`, `cheer` |
| `compound` | Cumulative progress of habits | `title`, `days`, `series [{label,color,values}]` |
| `hourglass` | Time leaking away, or aimed | `mode: leak/aim`, `labels` |
| `hours` | A day's waking hours, most leaking | `title`, `kept {index: label}`, `summary`, `firstHour` |
| `sort` | Two circles: up to you / not | `items [{text, side: in/out}]`, `mode: focus`, `note`, `inLabel`, `outLabel` |
| `breathe` | Guided in/out breathing | `in`, `out`, `cycles`, `lead`, `title` |
| `grid` | Franklin's virtue chart | `rows`, `mode: scatter/focus`, `weeks`, `density` |

The page is a pure function of time (`window.__seek(t)`), so renders are repeatable. Open
`renderer/runtime.html` in a browser and call `__setup(timeline)` to debug a scene.

### Narration

Videos render silent with burned-in captions until a voice key is set. With
`ELEVENLABS_API_KEY` (optional `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL`), each scene's line is
voiced, scene timing follows the real audio, and captions stay burned in so videos still
work muted. Audio is cached in `.cache/audio` by text and voice, so re-renders only pay for
changed lines. `--voice none` forces a silent render. Another provider plugs in by adding it
to `src/narration.mjs` (`synthesize(text) -> mp3 bytes`).

## Realistic films

1. **Plan.** `ANTHROPIC_API_KEY=... npm run film:plan -- <card-id>` asks Claude for a
   voice-over script and shot list (`film/schema.mjs`) and writes `film/plans/<card-id>.json`.
   Review and edit it. Two hand-written samples are there already.
2. **Preview for free.** `npm run film:render -- <card-id> --dry-run` prints every prompt;
   `--provider animatic` renders placeholder clips so pacing and captions can be checked.
3. **Render.** `FILM_PROVIDER=veo GEMINI_API_KEY=...` or `FILM_PROVIDER=runway RUNWAYML_API_SECRET=...`,
   then `npm run film:render -- <card-id>`. Each shot is generated once and cached; clips are
   cut to length, captions, credit and health note are burned in, narration is laid over, and
   the film ends on the same end card as the animated videos. Output: `out/<card-id>.film.mp4`.
4. **Publish.** Add `--publish` to make the film the card's explainer in `out/manifest.json`.

Model names (`VEO_MODEL`, `RUNWAY_MODEL`) and their accepted durations change often; check
the provider's docs before the first paid run. Video generation is billed per second of
footage, so review plans before rendering.

## Serving

The API reads `out/manifest.json` at startup (`EXPLAINER_DIR`, default
`../content/explainers/out`) and serves the files at `/media/explainers/`. To serve them from
a CDN instead, copy `out/` there and set `MEDIA_BASE_URL`.
