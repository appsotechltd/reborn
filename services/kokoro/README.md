# Kokoro speech service

Reads Reborn AI's replies aloud for free with Kokoro-82M (Apache-2.0), the same
model and approved voices as the explainer videos. It answers
`POST /v1/audio/speech` like OpenAI (`{"input","voice"}` → MP3), so the API only
needs `KOKORO_URL=http://kokoro:8880`. Voices outside the approved list are refused;
`KOKORO_VOICE` sets the default (`af_heart`).

It needs about 1.5 GB of RAM and uses every CPU core while it speaks. On 4 cores,
a 112-word reply (33 seconds of audio) takes about 11 seconds to make; each reply
is made once and saved, so hearing it again is instant. Requests are spoken one
at a time. If the service is down, the API falls back to OpenAI's voice.

    docker compose up -d kokoro
