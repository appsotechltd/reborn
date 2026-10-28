# Content pipeline

Fetches licensed source texts, validates idea cards and verifies their quotes. Python 3.11+,
standard library only (`jsonschema` is optional, for a cross-check against the backend's schema).

```sh
cd content/pipeline
python -m reborn_content fetch      # sources.toml -> ../build/passages/<id>.jsonl
python -m reborn_content validate   # ../library/*.json against ../SCHEMA.md + registry
python -m reborn_content verify     # every quote is verbatim in its fetched source
python -m unittest -v
```

## Adding a source

1. Check its licence is on the allow-list in [../SOURCES.md](../SOURCES.md).
2. Add a `[[source]]` entry to [sources.toml](sources.toml) with its adapter and expected licence.
3. `python -m reborn_content fetch <id>`; the adapter refuses it if the upstream licence differs.
4. Read `../build/passages/<id>.jsonl`, write `../library/<id>.json` (30–50 cards: fewer than 30 is flagged, more than 50 is rejected; our own words,
   quotes copied exactly with the passage's `locator`).
5. `validate` and `verify` until clean, then `stats --markdown > ../LIBRARY.md`.

Sources read by hand (`adapter = "web"`) can't be verified automatically, so their cards carry no
quotes.

## Layout

| Path | What |
|---|---|
| `sources.toml` | Registry: adapter, upstream location and expected licence per source |
| `reborn_content/adapters/` | `standardebooks`, `gutenberg`, `openstax`, `wikisource` (each also gates the licence) |
| `reborn_content/schema.py` | Validator for SCHEMA.md plus house rules |
| `reborn_content/passages.py` | Passage files and typography-insensitive quote matching |
| `tests/` | Offline tests with small fixtures |

`../.cache/` (HTTP cache) and `../build/` (passages, RAG export) are generated and git-ignored.
