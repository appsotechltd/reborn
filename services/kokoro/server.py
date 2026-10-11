"""Reborn's free speech service: Kokoro-82M (Apache-2.0) behind the same
POST /v1/audio/speech shape as OpenAI's text to speech, returning MP3.

The API calls it to read Reborn AI's replies aloud. It loads the model once
and runs on the CPU. Only the voices Reborn has approved can be used.

    KOKORO_MODEL=kokoro-v1.0.onnx KOKORO_VOICES=voices-v1.0.bin python server.py
"""
import json
import os
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import lameenc
import numpy as np
from kokoro_onnx import Kokoro

# The voices Moses approved (content/explainers/src/voices.mjs has the same list).
APPROVED = {
    "af_heart", "af_bella", "bf_emma", "am_michael", "bm_george", "af_sarah",
    "af_alloy", "af_nova", "am_adam", "am_echo", "am_eric", "am_liam",
}
DEFAULT_VOICE = os.environ.get("KOKORO_VOICE", "af_heart")
SPEED = float(os.environ.get("KOKORO_SPEED", "1.0"))
MAX_CHARS = 6000

kokoro = Kokoro(os.environ.get("KOKORO_MODEL", "kokoro-v1.0.onnx"),
                os.environ.get("KOKORO_VOICES", "voices-v1.0.bin"))
# One synthesis at a time: each already uses every core, and running two at
# once only makes both slower.
lock = threading.Lock()

_sentence = re.compile(r"(?<=[.!?])\s+")


def chunks(text: str, limit: int = 400):
    """Splits text at sentence ends into pieces Kokoro reads well."""
    piece = ""
    for s in _sentence.split(text.strip()):
        if piece and len(piece) + len(s) > limit:
            yield piece
            piece = ""
        piece = f"{piece} {s}".strip()
    if piece:
        yield piece


def speak(text: str, voice: str, speed: float) -> bytes:
    lang = "en-gb" if voice.startswith("b") else "en-us"  # bf_/bm_ voices are British
    enc = lameenc.Encoder()
    enc.set_bit_rate(64)
    enc.set_in_sample_rate(24000)
    enc.set_channels(1)
    enc.set_quality(5)
    out = bytearray()
    with lock:
        for piece in chunks(text):
            samples, rate = kokoro.create(piece, voice=voice, speed=speed, lang=lang)
            assert rate == 24000
            pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
            out += enc.encode(pcm)
    out += enc.flush()
    return bytes(out)


class Handler(BaseHTTPRequestHandler):
    def _error(self, status: int, message: str):
        body = json.dumps({"error": {"code": "bad_request", "message": message}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self._error(404, "not found")

    def do_POST(self):
        if self.path != "/v1/audio/speech":
            return self._error(404, "not found")
        try:
            n = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(min(n, 1 << 20)))
        except (ValueError, json.JSONDecodeError):
            return self._error(400, "send JSON")
        text = str(req.get("input", "")).strip()[:MAX_CHARS]
        voice = req.get("voice") or DEFAULT_VOICE
        if not text:
            return self._error(400, "input is empty")
        if voice not in APPROVED:
            return self._error(400, f"voice {voice} is not an approved voice")
        if req.get("response_format", "mp3") != "mp3":
            return self._error(400, "only mp3 is supported")
        speed = min(max(float(req.get("speed") or SPEED), 0.5), 2.0)
        audio = speak(text, voice, speed)
        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(audio)))
        self.end_headers()
        self.wfile.write(audio)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8880"))
    print(f"kokoro speech on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
