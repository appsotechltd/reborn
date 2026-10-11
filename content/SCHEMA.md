# Reborn content schema

This is the contract between the content library (`content/library/`) and the backend.
The backend's `reborn seed` command reads every `content/library/*.json` file, validates it
against these rules, and upserts it into Postgres. A file that breaks a rule is rejected
with a message naming the file, card and field.

Machine-readable version: [`schema/library-file.schema.json`](schema/library-file.schema.json) (JSON Schema 2020-12).

## File layout

One file per source: `content/library/<source-id>.json`.

```json
{
  "source": { ... },
  "cards": [ { ... }, { ... } ]
}
```

Each source should have at least 30 cards, and up to 50 when the source has enough ideas. The validator warns below 30 (so a short source still loads) and rejects 0 or more than 50.

## Source

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Lowercase slug, `^[a-z0-9]+(-[a-z0-9]+)*$`, max 80. Must equal the file name. e.g. `meditations-marcus-aurelius` |
| `title` | string | yes | e.g. `Meditations` |
| `authors` | string[] | yes | At least one. e.g. `["Marcus Aurelius"]`, `["OpenStax"]` |
| `kind` | enum | yes | `book`, `textbook`, `article`, `guide`, `study`, `talk`, `podcast`, `video` |
| `url` | string (https URL) | yes | Where a reader can find the source |
| `licence` | enum | yes | See licences below |
| `licence_url` | string (URL) | yes | The licence page or the source's own licence/terms page |
| `attribution` | string | yes | The exact credit line shown on every card, e.g. `NHS, How to fall asleep faster and sleep better, Open Government Licence v3.0` |
| `publisher` | string | no | e.g. `Project Gutenberg`, `OpenStax`, `NHS` |
| `year` | integer | no | Original publication year (negative for BCE) |
| `language` | string | no | BCP-47, default `en` |
| `translator` | string | no | For translated public-domain works |
| `retrieved_at` | string (date `YYYY-MM-DD`) | yes | When the licence was checked |
| `notes` | string | no | Anything a reviewer should know about the licence |

### Licences

| Code | Meaning | Quotes allowed |
|---|---|---|
| `public-domain` | Public-domain work (Gutenberg, Standard Ebooks, pre-1929 etc.) | yes |
| `us-gov-public-domain` | US federal government work (NIH, CDC, MedlinePlus pages that are PD) | yes |
| `cc-by-4.0` | Creative Commons Attribution 4.0 (many OpenStax books and PLOS/PMC articles; check each, some OpenStax titles are CC BY-NC-SA) | yes |
| `cc-by-3.0` | Creative Commons Attribution 3.0 | yes |
| `cc-by-sa-4.0` | Creative Commons Attribution-ShareAlike 4.0 (Wikipedia). Cards adapted from it are shared under CC BY-SA too | yes |
| `cc0-1.0` | CC0 public-domain dedication | yes |
| `ogl-3.0` | UK Open Government Licence v3.0 (NHS) | yes |
| `original-summary` | "Free to read, summarise only" sources (blogs, talks, podcasts, modern bestsellers). Cards are our own words with a link back | **no** |

Non-commercial licences (any `*-nc-*`, e.g. WHO CC BY-NC-SA) are **rejected**: the app may charge or show ads.

## Card

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | `<source-id>--<nn>` e.g. `meditations-marcus-aurelius--01`. Stable forever: user stashes and reviews point at it |
| `topic` | enum | yes | Primary topic, see topics below |
| `tags` | string[] | no | Lowercase slugs, max 8, e.g. `["stoicism","anger"]` |
| `title` | string | yes | The idea in one line, max 90 chars |
| `body` | string | yes | The idea in our own words, 25–160 words (about a minute to read), max 1200 chars. Plain text; blank line separates paragraphs |
| `quote` | string | no | Short verbatim quote, max 300 chars. Only for licences where quotes are allowed (not `original-summary`) |
| `apply_it` | string | yes | One small action or reflection question, max 240 chars |
| `locator` | string | no | Where in the source, e.g. `Book II, 1` or `Chapter 14.3` |
| `quiz` | object | no | See quiz below. Strongly encouraged: powers review and quizzes |
| `health` | boolean | no | Default `false`. Set `true` for any card about physical or mental health; the app then shows "This is general information, not medical advice." Must be `true` when `topic` is `health` |
| `language` | string | no | BCP-47, defaults to the source's language |

### Quiz

| Field | Type | Required | Notes |
|---|---|---|---|
| `question` | string | yes | max 200 chars |
| `options` | string[] | yes | 2–4 options, each max 120 chars |
| `answer` | integer | yes | Zero-based index into `options` |
| `explanation` | string | no | Shown after answering, max 300 chars |

### Topics

| Slug | Name |
|---|---|
| `business` | Business |
| `psychology` | Psychology |
| `mental-strength` | Mental Strength & Resilience |
| `health` | Health & Wellness |
| `emotional-intelligence` | Emotional Intelligence |
| `personal-development` | Personal Development |
| `productivity` | Productivity & Career |
| `money` | Money |
| `relationships` | Relationships |
| `dating-marriage` | Dating & Marriage |
| `mindfulness` | Mindfulness & Philosophy |
| `faith-wisdom` | Faith & Wisdom |
| `leadership` | Leadership |
| `parenting` | Parenting & Family |
| `communication` | Communication & Influence |
| `creativity` | Creativity |
| `learning` | Learning & Thinking |
| `lives-history` | Lives & History |
| `entrepreneurship` | Entrepreneurship |
| `heartbreak-healing` | Heartbreak & Healing |
| `grief-loss` | Grief & Loss |
| `study-smarter` | Study Smarter |
| `skills-mastery` | Skills & Mastery |

`relationships` covers friendship, family ties and getting along with people in general; `dating-marriage` is dating, courtship, marriage and keeping love strong; `parenting` includes responsible, intentional parenting; `mental-strength` is mental toughness, discipline, focus, resilience and mental wellbeing; `learning` is clear reasoning and thinking well, while `study-smarter` is how to learn, revise, take exams and manage time as a student, and `skills-mastery` is picking up new skills fast and practising well; `heartbreak-healing` is breakups, divorce and starting over; `grief-loss` is bereavement, mourning and coping.

Cards in `heartbreak-healing` and `grief-loss` always show a support note pointing to people who can help, in place of the health disclaimer. Write them gently.

## Example

```json
{
  "source": {
    "id": "meditations-marcus-aurelius",
    "title": "Meditations",
    "authors": ["Marcus Aurelius"],
    "translator": "George Long",
    "kind": "book",
    "url": "https://www.gutenberg.org/ebooks/2680",
    "licence": "public-domain",
    "licence_url": "https://www.gutenberg.org/policy/license.html",
    "attribution": "Marcus Aurelius, Meditations (trans. George Long), Project Gutenberg, public domain",
    "publisher": "Project Gutenberg",
    "year": 180,
    "language": "en",
    "retrieved_at": "2026-10-10"
  },
  "cards": [
    {
      "id": "meditations-marcus-aurelius--01",
      "topic": "mindfulness",
      "tags": ["stoicism", "difficult-people"],
      "title": "Expect difficult people before the day starts",
      "body": "Each morning, Marcus reminded himself that he would meet people who are rude, ungrateful or dishonest. He wasn't being cynical. Naming it in advance took the surprise out of it, so he could respond calmly instead of reacting.\n\nThey act that way, he reasoned, because they don't know better, and being angry with them only harms you.",
      "quote": "Begin the morning by saying to thyself, I shall meet with the busy-body, the ungrateful, arrogant, deceitful, envious, unsocial.",
      "apply_it": "Before your next meeting, name one way it could go badly and decide now how you will respond.",
      "locator": "Book II, 1",
      "quiz": {
        "question": "Why did Marcus expect to meet difficult people each morning?",
        "options": ["To avoid them", "So their behaviour wouldn't catch him off guard", "To judge them"],
        "answer": 1,
        "explanation": "Anticipating it let him respond calmly rather than react."
      }
    }
  ]
}
```

## Rules the validator enforces

- Source `id` matches the file name; card ids are unique across the library and start with `<source-id>--`.
- `licence` is one of the codes above; anything containing `nc` is rejected.
- `quote` is absent when `licence` is `original-summary`.
- `health` is `true` whenever `topic` is `health`.
- `quiz.answer` is a valid index into `quiz.options`.
- Body length 25–160 words.
- 1–50 cards per source; fewer than 30 is a warning.
