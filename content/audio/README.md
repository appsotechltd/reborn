# Card audio

Every card is read aloud for the Listen button and Listen mode, in one of the approved voices
(see `content/explainers/src/voices.mjs`). Each book has one voice, so a book always sounds the
same; `voices.json` sets it, with a short reason per voice. Cards whose book isn't listed use
`default` (Heart).

A recording reads the title, the body, "Apply it." and the tip, the support or health note when the
card has one, and "From <source>, by <authors>." It is mono 64 kbps mp3 at -16 LUFS, about 300 KB
for a 40-second card. There are no captions or transcripts.

## Render

Kokoro-82M runs locally and is free. Set it up once with `content/explainers/tools/setup-kokoro.sh`.

```sh
KOKORO_DIR=content/explainers/.cache/kokoro \
  content/explainers/.cache/kokoro/venv/bin/python content/audio/render_audio.py --jobs 2
```

It writes `out/<card-id>.mp3` and `out/manifest.json`. A card is voiced again only when its text, its
book's voice or the speed changes, so nothing is rendered twice. `--only <card-id> ...` limits a run.
A full library of about 2,600 cards takes a few hours on a 4-core machine.

## Publish

Upload the recordings before deploying a new manifest, because on R2 the API advertises every card in it:

```sh
reborn media-upload content/audio/out audio
```

Only `out/manifest.json` is committed. The API reads it at startup (`CARD_AUDIO_DIR`, default
`../content/audio/out`) and adds an `audio` object to each card (see `docs/API.md`).

## Background music

The optional background music Listen mode can play under the voice (off unless the listener turns
it on) is Chopin's Nocturne in E-flat major, Op. 9 No. 2, from Musopen's Complete Chopin
Collection (https://archive.org/details/musopen-chopin), released under CC0 1.0
(https://creativecommons.org/publicdomain/zero/1.0/). No credit is required.

`listen-music.mp3` (in web/public/audio and app/assets/audio) is that recording, lightly
compressed, faded at both ends so the loop is smooth, and turned down to about -34 LUFS (about
17 dB under the card voices), mono 64 kbps:

    ffmpeg -i "Nocturne Op. 9 no. 2 in E flat major.mp3" \
      -af "acompressor=threshold=-24dB:ratio=3:attack=50:release=800,highpass=f=60,volume=-6.4dB,afade=t=in:d=2,afade=t=out:st=271.6:d=5" \
      -ac 1 -b:a 64k listen-music.mp3
