"""Synthesise speech with Kokoro-82M (Apache-2.0 weights) through kokoro-onnx.

Reads JSON lines from stdin, one per clip: {"text": ..., "out": "file.wav"}.
Loads the model once, so a whole video is voiced in one run.

    python kokoro_tts.py <model.onnx> <voices.bin> <voice> <speed> < jobs.jsonl
"""
import json
import sys

import soundfile as sf
from kokoro_onnx import Kokoro


def main() -> None:
    model, voices, voice, speed = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
    kokoro = Kokoro(model, voices)
    lang = "en-gb" if voice.startswith("b") else "en-us"  # bf_/bm_ voices are British
    for line in sys.stdin:
        if not line.strip():
            continue
        job = json.loads(line)
        samples, rate = kokoro.create(job["text"], voice=voice, speed=speed, lang=lang)
        sf.write(job["out"], samples, rate)
        print(job["out"], flush=True)


if __name__ == "__main__":
    main()
