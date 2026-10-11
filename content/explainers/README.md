# Explainer videos

Short vertical videos (9:16, about a minute) that dramatise an idea card. The API attaches
each video to its card as `explainer` (see `docs/API.md`), and the web and mobile card views
play it above the card text.

Two kinds:

- **Animated explainers** (`kind: "animated"`), rendered here from original illustrated scenes.
  Five are rendered (`out/manifest.json` lists them; the files live in the media bucket, not git).
- **Realistic films** (`kind: "film"`), shot by a text-to-video model from a reviewed plan.
  The pipeline is ready but unused until a Veo or Runway key is set.

Every video credits its source on screen the whole time, ends on a card with the full credit
and licence, and health cards keep "General information, not medical advice" on screen plus
the full disclaimer at the end. Illustrations are drawn from scratch: no book covers or
copyrighted imagery. Videos have no captions, on screen or as a caption track, because they
hide the picture. Each render writes the video and a `.jpg` poster (the title frame); upload both
to the media bucket with `reborn media-upload content/explainers/out explainers`.

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
npm run render -- aesops-fables--07   # out/<id>.mp4 + .jpg poster, updates out/manifest.json
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

Videos are narrated in one of the **approved voices** (`src/voices.mjs`), the only voices Reborn
uses. Pick whichever suits the card with `"voice"` in its script or `--voice <name>`; the default
is `heart`.

| Engine | Voices |
|---|---|
| Kokoro | `heart`, `bella`, `emma`, `michael`, `george`, `sarah`, `alloy`, `nova`, `adam`, `echo`, `eric`, `liam` |
| Chatterbox | `heart-chatterbox`, `bella-chatterbox`, `george-chatterbox` |

Both engines are free and run locally. **Kokoro-82M** (Apache-2.0) is fast on a CPU. **Chatterbox**
(MIT) is more expressive and slower. Its three voices are copies of the Kokoro voices with the
same names: Chatterbox clones a short clip that Kokoro reads first (cached in `.cache/voices`).

```sh
tools/setup-kokoro.sh          # Python venv + model files (about 350 MB) in .cache/kokoro
tools/setup-chatterbox.sh      # only for the Chatterbox voices; needs huggingface.co
npm run render -- --voice george
```

`KOKORO_SPEED` sets the pace (default 0.95). Scene timing follows the real audio. `--voice none`
renders silently, with timings from reading speed. Audio is cached in `.cache/audio` by text and
voice, so re-renders only voice the lines that changed.

## Looks

`--theme` (or `"theme"` in a script) renders in a dark look instead of the default paper style:
`voltage`, `ember` and `aurora` paint animated backgrounds and draw figures as glowing line art;
`swarm` and `depth` gather 2D or 3D particles into a shape per shot (`params.shape` /
`params.object`); `photo` moves slowly through cinematic stills (`params.image`). A scene can change
shot on a word of its narration with `params.beats: [{ "word": "drifting", "image": {...} }]`.

`photo` is the house style for story and philosophy cards (Seneca, Epictetus, Franklin, Aesop).
Cards whose animation does the teaching, such as the NHS breathing guide, keep their animated look.

`"score": true` adds original music and sound effects composed by `tools/score.py` (numpy), mixed
under the voice.

Photo images come from one of three providers, each read from its own key. Every image is paid
for once and kept forever. It is saved under `images/` in the media bucket (R2, using the same
`R2_*` settings as the API) and in `.cache/images`, keyed by provider, model, size and prompt. A
saved image is always reused, on any machine. Only `--regenerate-images` makes new ones.

| Provider | Key | Default for |
|---|---|---|
| OpenAI (`gpt-image-1` at medium quality; `OPENAI_IMAGE_MODEL`, `OPENAI_IMAGE_QUALITY`) | `OPENAI_API_KEY` | photoreal shots and card art |
| Ideogram 3.0 | `IDEOGRAM_API_KEY` | images with words in them (`image: { prompt, text }`), such as quote images |
| Google Imagen (`IMAGEN_MODEL`) | `GEMINI_API_KEY` | fallback |

When the preferred provider has no key, the next one that does is used. Force one for a whole render with
`--image-provider openai|ideogram|imagen` or `IMAGE_PROVIDER`, or for one image with `provider` on it.
Check each provider's current prices before a large run. Style samples render to `out/samples/`:

```sh
OPENAI_API_KEY=... node src/render.mjs --sample samples/seneca-photo.json --image-provider openai
node src/images.mjs "A dark stone wall at dusk" --text "Life is long enough" --out quote.png
```

## Realistic films

1. **Plan.** `ANTHROPIC_API_KEY=... npm run film:plan -- <card-id>` asks Claude for a
   voice-over script and shot list (`film/schema.mjs`) and writes `film/plans/<card-id>.json`.
   Review and edit it. Two hand-written samples are there already.
2. **Preview for free.** `npm run film:render -- <card-id> --dry-run` prints every prompt;
   `--provider animatic` renders placeholder clips so pacing can be checked.
3. **Render.** `FILM_PROVIDER=veo GEMINI_API_KEY=...` or `FILM_PROVIDER=runway RUNWAYML_API_SECRET=...`,
   then `npm run film:render -- <card-id>`. Each shot is generated once and cached; clips are
   cut to length, the credit and health note are burned in, narration is laid over, and
   the film ends on the same end card as the animated videos. Output: `out/<card-id>.film.mp4`.
4. **Publish.** Add `--publish` to make the film the card's explainer in `out/manifest.json`.

Model names (`VEO_MODEL`, `RUNWAY_MODEL`) and their accepted durations change often; check
the provider's docs before the first paid run. Video generation is billed per second of
footage, so review plans before rendering.

## Serving

The API reads `out/manifest.json` at startup (`EXPLAINER_DIR`, default
`../content/explainers/out`) and links each card to its files in the media store under
`explainers/`. Upload them with `reborn media-upload content/explainers/out explainers`: that
puts them in Cloudflare R2 when the `R2_*` keys are set, or in the local `MEDIA_DIR` (served by
the API at `/media/`) in development. Locally, a card whose video has not been uploaded gets no
explainer. Rendered files are not committed to git; render them or fetch them from the bucket.
