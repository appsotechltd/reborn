"""Synthesise speech with Chatterbox (Resemble AI, MIT licence) on the CPU.

Reads JSON lines from stdin, one per clip: {"text": ..., "out": "file.wav"}.
Loads the model once, so a whole video is voiced in one run. The model files are
fetched from Hugging Face on first use (huggingface.co must be reachable).

    python chatterbox_tts.py <exaggeration> <cfg_weight> [reference.wav] < jobs.jsonl

exaggeration: 0.25-2.0, higher is more dramatic (0.5 is neutral).
cfg_weight:   lower slows and steadies the delivery (0.3 suits narration).
reference:    optional few-second clip of a voice to speak in.
"""
import json
import sys

import torchaudio
from chatterbox.tts import ChatterboxTTS


def main() -> None:
    exaggeration, cfg = float(sys.argv[1]), float(sys.argv[2])
    ref = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
    model = ChatterboxTTS.from_pretrained(device="cpu")
    for line in sys.stdin:
        if not line.strip():
            continue
        job = json.loads(line)
        wav = model.generate(job["text"], audio_prompt_path=ref, exaggeration=exaggeration, cfg_weight=cfg)
        torchaudio.save(job["out"], wav, model.sr)
        print(job["out"], flush=True)


if __name__ == "__main__":
    main()
