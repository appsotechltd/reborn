# Reborn AI units and pricing

Prices checked on 2026-10-11 from OpenAI's official pricing pages (Standard tier, USD):
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/guides/image-generation (per-image table)
- https://developers.openai.com/api/docs/models/gpt-image-1, /gpt-5.4-mini, /gpt-4o-mini-tts

## 1. What OpenAI charges for what Reborn AI would use

| Job | Model | OpenAI price |
|---|---|---|
| Text chat with function calling | `gpt-5.4-mini` (recommended) | $0.75 in, $0.075 cached in, $4.50 out per 1M tokens |
| Cheaper text option | `gpt-6-luna` | $0.10 in, $0.01 cached in, $0.50 out per 1M tokens |
| Higher quality text option | `gpt-6-sol` | $2.00 in, $0.20 cached in, $10.00 out per 1M tokens |
| Voice: speech to text | `gpt-4o-mini-transcribe` | about $0.003 per minute |
| Voice: text to speech | `gpt-4o-mini-tts` | $0.60 per 1M text tokens in, $12.00 per 1M audio tokens out |
| Live voice (talk back and forth) | `gpt-realtime-2.1-mini` | audio $10 in / $20 out per 1M tokens |
| Sketch | `gpt-image-1-mini`, low quality | $0.005 to $0.006 per image |
| Illustration | `gpt-image-1-mini`, medium quality | $0.011 to $0.015 per image |
| Picture (photo-like) | `gpt-image-2`, medium quality | $0.041 (portrait or landscape) to $0.053 (square) per image |
| (what the explainers use now) | `gpt-image-1`, medium quality | $0.042 (square) to $0.063 (portrait) per image |
| Graphs and charts | no image model: the AI writes the chart data through function calling and the app draws it | text tokens only |
| Web search tool (not planned) | built-in | $10 per 1,000 calls plus tokens |

## 2. What one action costs us (estimates)

These are worked out from the prices above. Token counts per message are my estimates, not OpenAI figures.

| Action | Assumption | Our cost |
|---|---|---|
| Text message | about 4,000 tokens in (2,500 of them cached instructions and tools, plus library cards and chat history), 500 out, sometimes a second round after a tool call | $0.003 to $0.008 |
| Chart or graph | same as a text message, with the chart data in the reply | $0.003 to $0.008 |
| Voice, per minute of audio | transcribe ($0.003) + speak back (about 1,250 audio tokens per minute, so about $0.015) + the text reply | about $0.02 |
| Sketch | gpt-image-1-mini low | $0.006 |
| Illustration | gpt-image-1-mini medium | $0.015 |
| Picture | gpt-image-2 medium | $0.041 to $0.053 |

## 3. Recommended AI unit rates

One AI unit covers about $0.005 of OpenAI cost.

| Action | AI units |
|---|---|
| Each reply | 1 |
| Chart or graph in a reply | 1 more |
| Voice messages you send | 1 per started 30 words (about 5 a minute). A 20-word voice question is 1 unit to hear. |
| Listening to a reply | Free. Our own Kokoro voice (Heart) reads it, so it costs us only server time; OpenAI reads it only if Kokoro is down. |
| Sketch in a reply | 2 more |
| Illustration in a reply | 4 more |
| Picture in a reply | 12 more |

If a member doesn't have enough units for a picture or chart, Reborn AI answers in words for 1 unit and says they can top up.

## 4. Recommended premium allowance

Keep premium at the current prices ($4.99 a month, $39.99 a year) and include **250 AI units a month** on both plans. The allowance refills on the 1st of each month (UTC) and does not roll over.

250 units is about 250 text messages, or 50 minutes of voice, or 20 pictures. At $0.005 a unit, a member who uses every unit costs us about $1.25 a month. Most people will use far less. Long chats are the one thing that can cost more than a unit is worth, so the server only sends the last 20 turns of a chat to the model.

| Plan | You receive (after store or card fees) | AI cost if every unit is used |
|---|---|---|
| Monthly $4.99 | $3.49 (store 30%) to $4.54 (Stripe) | $1.25 |
| Yearly $39.99 | $2.33 to $3.21 a month | $1.25 |

The yearly plan is the tight one. If margins matter more than generosity, give yearly 200 units a month instead.

## 5. Recommended pay-as-you-go top-ups

Top-up units never expire and are used only after the monthly allowance runs out. They can be used while premium is active.

| Pack | Price | Per unit | AI cost if every unit is used | Margin after 30% store cut | Margin on Stripe |
|---|---|---|---|---|---|
| 250 units | $2.99 | 1.2c | $1.25 | 40% | 52% |
| 600 units | $5.99 | 1.0c | $3.00 | 28% | 46% |
| 1,300 units | $11.99 | 0.92c | $6.50 | 23% | 43% |

Apple and Google take 15% instead of 30% for small businesses (under $1M a year) and for subscriptions after the first year, so real margins are higher than the store column.

## 6. OpenAI or Claude for the text chat

Claude prices (Anthropic, 2026-10): Haiku 5.5 $0.10 / $0.50, Sonnet 5.5 $2 / $10, Opus 5.5 $4 / $20 per 1M tokens. Claude Haiku 5.5 costs the same as OpenAI's cheapest `gpt-6-luna`, and Sonnet 5.5 the same as `gpt-6-sol`. The free AI guide already runs on Claude Opus 5.5, which costs about three times more per message than `gpt-5.4-mini`. Images and voice need OpenAI either way. The build uses OpenAI for everything in Reborn AI, as asked, with the text model set by `OPENAI_CHAT_MODEL` so it can be switched without code changes.

## 7. Ways to cut cost

- Done: replies are read aloud by our own Kokoro service (`services/kokoro`, voice Heart), so listening is free for members and costs us only server time. OpenAI's voice is the fallback when Kokoro is down. Voice messages members send still cost 1 unit per 30 words, because transcription stays on OpenAI.
- Done: pictures are saved by model, size and prompt, so the same picture is never paid for twice, whoever asks.
- OpenAI's Batch API halves text prices, but it is too slow for chat.

## 7. The card studio (media for cards members write)

Prices checked against the same OpenAI pricing as above (2026-10-15).

| Action | What it uses | Our cost | AI units |
|---|---|---|---|
| Sketch | `gpt-image-1-mini` low, landscape | about $0.006 | 2 |
| Illustration | `gpt-image-1-mini` medium, landscape | about $0.015 | 4 |
| Photo-like picture | `gpt-image-2` medium, landscape | $0.041 | 12 |
| Audio (the card read aloud) | our own Kokoro voice; OpenAI `gpt-4o-mini-tts` (about $0.015 a minute) only when Kokoro is down | $0 to $0.015 a minute | 1 per started 50 words (3 for a one-minute card) |
| Illustrated video | 1 chat call to plan 4 scenes (about $0.003), 4 portrait illustrations (about $0.06), and the audio | about $0.06 to $0.08 | 1 + 16 + the audio (20 for a one-minute card) |

The video plays in the apps as four illustrations that slowly drift and cross-fade over the
narration, so no video file has to be rendered on the server. Every image and recording is
saved in R2 and reused, never paid for twice.

What 250 monthly units buy: about 12 one-minute videos, or 62 illustrations, or 125 sketches,
or 20 photo-like pictures, or 83 one-minute audios, or any mix.
