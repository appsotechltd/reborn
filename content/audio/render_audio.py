"""Voice every library card for the Listen button and Listen mode, with Kokoro-82M.

Each book has one voice from the approved list, set in voices.json (default Heart).

    python render_audio.py [--library ../library] [--out out] [--jobs 4] [--only ID ...]

Writes out/<card-id>.mp3 (mono, 64 kbps, -16 LUFS) and out/manifest.json. A card is
re-voiced only when its spoken text, voice or speed changes, so nothing is rendered
twice. Upload the folder with `reborn media-upload content/audio/out audio`; the API
reads the manifest (CARD_AUDIO_DIR) and adds an "audio" object to each card.

Needs the Kokoro venv from content/explainers/tools/setup-kokoro.sh (KOKORO_DIR).
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEED = 1.0
VOICES = json.loads((HERE / "voices.json").read_text())
# Mirrors content/explainers/src/voices.mjs (Moses's approved Kokoro voices).
APPROVED = {"af_heart", "af_bella", "bf_emma", "am_michael", "bm_george", "af_sarah", "af_alloy",
            "af_nova", "am_adam", "am_echo", "am_eric", "am_liam"}
PAUSE_S = 0.5

# Mirrors backend/internal/content/types.go.
SUPPORT_TOPICS = {"heartbreak-healing", "grief-loss"}
SUPPORT_NOTE = ("If you're finding things hard, you don't have to go through it alone. Talk to someone you "
                "trust, or reach out to a counsellor, your doctor or a local support line.")
HEALTH_DISCLAIMER = ("This is general information, not medical advice. Talk to a qualified health "
                     "professional about your own situation.")


def join_names(names):
    names = [n for n in names if n]
    if len(names) <= 1:
        return "".join(names)
    return ", ".join(names[:-1]) + " and " + names[-1]


def spoken_parts(card, source):
    """The paragraphs read aloud, in order. Same order as the app's Listen button."""
    parts = [card["title"].rstrip(".") + "."]
    parts += [p.strip() for p in card["body"].split("\n\n") if p.strip()]
    if card.get("apply_it"):
        parts.append("Apply it. " + card["apply_it"].strip())
    if card.get("topic") in SUPPORT_TOPICS:
        parts.append(SUPPORT_NOTE)
    elif card.get("health") or card.get("topic") == "health":
        parts.append(HEALTH_DISCLAIMER)
    by = join_names(source.get("authors") or [])
    parts.append(f"From {source['title']}" + (f", by {by}." if by else "."))
    return parts


def load_cards(library):
    for f in sorted(Path(library).glob("*.json")):
        data = json.loads(f.read_text())
        for card in data["cards"]:
            yield card["id"], (voice_for(data["source"]["id"]), spoken_parts(card, data["source"]))


def voice_for(source_id):
    voice = VOICES["sources"].get(source_id, VOICES["default"])
    if voice not in APPROVED:
        raise SystemExit(f"{source_id}: {voice} is not an approved voice")
    return voice


def digest(voice, parts):
    h = hashlib.sha256(f"{voice}@{SPEED}\n".encode())
    h.update("\n\n".join(parts).encode())
    return h.hexdigest()[:16]


_kokoro = None


def render(job):
    """Runs in a worker process. Returns (id, duration_s)."""
    global _kokoro
    import numpy as np
    import soundfile as sf
    from kokoro_onnx import Kokoro

    card_id, voice, parts, out = job
    kdir = Path(os.environ.get("KOKORO_DIR", HERE.parent / "explainers" / ".cache" / "kokoro"))
    if _kokoro is None:
        _kokoro = Kokoro(str(kdir / "kokoro-v1.0.onnx"), str(kdir / "voices-v1.0.bin"))
    audio, rate = [], 24000
    for p in parts:
        samples, rate = _kokoro.create(p, voice=voice, speed=SPEED, lang="en-gb" if voice.startswith("b") else "en-us")
        audio += [samples, np.zeros(int(rate * PAUSE_S), dtype=samples.dtype)]
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        sf.write(wav, np.concatenate(audio[:-1]), rate)
        mp3 = Path(out) / f"{card_id}.mp3"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-af", "loudnorm=I=-16:TP=-1.5",
                        "-ac", "1", "-c:a", "libmp3lame", "-b:a", "64k", str(mp3)], check=True)
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                str(mp3)], check=True, capture_output=True, text=True).stdout)
    return card_id, round(dur, 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--library", default=str(HERE.parent / "library"))
    ap.add_argument("--out", default=str(HERE / "out"))
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    mpath = out / "manifest.json"
    manifest = json.loads(mpath.read_text()) if mpath.exists() else {}
    entries = manifest.get("cards", {})

    cards = dict(load_cards(args.library))
    todo = []
    for cid, (voice, parts) in cards.items():
        if args.only and cid not in args.only:
            continue
        e = entries.get(cid)
        if e and e.get("hash") == digest(voice, parts) and (out / e["file"]).exists():
            continue
        todo.append((cid, voice, parts, str(out)))
    print(f"{len(cards)} cards, {len(todo)} to voice", flush=True)

    def save():
        m = {"version": 1, "engine": f"kokoro-82m@{SPEED}",
             "cards": {k: entries[k] for k in sorted(entries) if k in cards}}
        tmp = mpath.with_suffix(".tmp")
        tmp.write_text(json.dumps(m, indent=1) + "\n")
        tmp.replace(mpath)

    with ProcessPoolExecutor(args.jobs) as pool:
        for i, (cid, dur) in enumerate(pool.map(render, todo), 1):
            voice = cards[cid][0]
            entries[cid] = {"file": f"{cid}.mp3", "duration_s": dur, "voice": voice, "hash": digest(*cards[cid])}
            if i % 20 == 0 or i == len(todo):
                save()
                print(f"{i}/{len(todo)}", flush=True)
    save()


if __name__ == "__main__":
    sys.exit(main())
