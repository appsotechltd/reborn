#!/usr/bin/env python3
"""Composes an original music bed and sound effects for an explainer, timed to its edit.

    python3 tools/score.py plan.json out.wav

plan.json: {"duration": 39.3, "scenes": [{"start": 0, "duration": 5.2, "lift": false}],
            "beats": [{"at": 7.4, "big": false}], "seed": 1}

Everything is synthesised here from sine waves and noise, so the result is ours to use
with no licence to track. Deterministic for a given plan. Needs only numpy.
"""
import json
import sys
import wave

import numpy as np

SR = 44100


def note(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env_adsr(n, a, r):
    e = np.ones(n)
    na, nr = int(a * SR), int(r * SR)
    if na: e[:na] = np.linspace(0, 1, na) ** 2
    if nr: e[-nr:] *= np.linspace(1, 0, nr) ** 2
    return e


def pad_voice(freq, n, rng, bright=1.0):
    """A warm detuned pad: a few saw-like partials per voice, three voices slightly detuned."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for det in (-0.07, 0.0, 0.06):
        f = freq * 2 ** (det / 12)
        ph = rng.random() * 2 * np.pi
        for k in range(1, 9):
            amp = (1 / k) * np.exp(-k / (2.2 + 2.5 * bright))
            out += amp * np.sin(2 * np.pi * f * k * t + ph * k)
    return out * (1 + 0.15 * np.sin(2 * np.pi * 0.2 * t + rng.random() * 6))


def one_pole_lowpass(x, cutoff):
    """Lowpass with a per-sample cutoff in Hz (array or float)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def reverb(x, rng, seconds=2.8, mix=0.35):
    """Convolution with decaying noise: a big, soft hall. Separate IRs per channel give width."""
    n = int(seconds * SR)
    decay = np.exp(-np.linspace(0, 7, n))
    outs = []
    for _ in range(2):
        ir = rng.standard_normal(n) * decay
        ir = one_pole_lowpass(ir, 5000.0)
        ir /= np.sqrt((ir ** 2).sum())
        size = 1 << int(np.ceil(np.log2(len(x) + n)))
        wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
        outs.append((1 - mix) * x + mix * wet * 0.9)
    return np.stack(outs, axis=1)


def whoosh(rng, dur=0.9, big=False):
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    noise = rng.standard_normal(n)
    sweep = 300 + (5200 if big else 3200) * np.sin(np.pi * t) ** 2
    body = one_pole_lowpass(noise, sweep) - one_pole_lowpass(noise, sweep * 0.25)
    return body * np.sin(np.pi * t) ** 1.5 * (0.3 if big else 0.16)


def impact(rng, big=False):
    dur = 2.2 if big else 1.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 55 * np.exp(-t * 3) + 32  # pitch drops: a deep thud
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * (2.2 if big else 4))
    click = one_pole_lowpass(rng.standard_normal(n), 2500.0) * np.exp(-t * 40) * 0.6
    return (sub * (0.9 if big else 0.5) + click * (0.5 if big else 0.25))


def riser(rng, dur=1.6):
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    noise = one_pole_lowpass(rng.standard_normal(n), 400 + 6000 * t ** 2)
    tone = np.sin(2 * np.pi * np.cumsum(220 + 660 * t ** 2) / SR) * 0.15
    return (noise * 0.35 + tone) * t ** 2.5


def place(track, clip, at):
    i = int(at * SR)
    if i >= len(track): return
    j = min(len(track), i + len(clip))
    if i < 0:
        clip, i = clip[-i:], 0
        j = min(len(track), len(clip))
    track[i:j] += clip[: j - i]


def compose(plan):
    rng = np.random.default_rng(plan.get("seed", 1))
    dur = plan["duration"] + 0.5
    n = int(dur * SR)
    music = np.zeros(n)

    # Chords: D minor (i VI III VII) for the problem, lifting to F major (I V vi IV) where a scene says "lift".
    minor = [[50, 57, 62, 65], [46, 53, 58, 62], [53, 57, 60, 65], [48, 55, 60, 64]]
    major = [[53, 60, 65, 69], [48, 55, 60, 64], [50, 57, 62, 65], [46, 53, 58, 65]]
    lift_from = next((s["start"] for s in plan["scenes"] if s.get("lift")), None)
    chord_len = 4.8
    k = 0
    t0 = 0.0
    while t0 < dur:
        lifted = lift_from is not None and t0 >= lift_from - 0.5
        chord = (major if lifted else minor)[k % 4]
        seg = int((chord_len + 1.6) * SR)
        e = env_adsr(seg, 1.4, 1.8)
        voice = sum(pad_voice(note(m), seg, rng, bright=1.6 if lifted else 1.0) for m in chord) / len(chord)
        place(music, voice * e * 0.22, t0)
        # Sub drone on the root.
        tt = np.arange(seg) / SR
        place(music, np.sin(2 * np.pi * note(chord[0] - 12) * tt) * e * 0.16, t0)
        # A soft plucked arpeggio once the story is moving.
        if t0 > 3:
            step = 60 / 84 / 2
            for j in range(int(chord_len / step)):
                m = chord[[0, 2, 1, 3, 2, 1, 3, 2][j % 8]] + 12
                pn = int(1.1 * SR)
                pt = np.arange(pn) / SR
                pluck = np.sin(2 * np.pi * note(m) * pt) * np.exp(-pt * 5) + 0.3 * np.sin(4 * np.pi * note(m) * pt) * np.exp(-pt * 9)
                place(music, pluck * (0.06 if not lifted else 0.085) * (0.6 + 0.4 * ((j % 4) == 0)), t0 + j * step)
        t0 += chord_len
        k += 1

    music = one_pole_lowpass(music, 6500.0)
    # Fade in under the title and out after the end card.
    fade = np.ones(n)
    fade[: int(1.5 * SR)] = np.linspace(0, 1, int(1.5 * SR))
    fade[-int(2.5 * SR):] *= np.linspace(1, 0, int(2.5 * SR))
    music *= fade

    sfx = np.zeros(n)
    for i, s in enumerate(plan["scenes"]):
        if i == 0:
            place(sfx, impact(rng, big=True), s["start"] + 0.15)
            continue
        if s.get("lift"):
            place(sfx, riser(rng), s["start"] - 1.6)
        place(sfx, whoosh(rng, big=True), s["start"] - 0.45)
        place(sfx, impact(rng, big=bool(s.get("lift"))), s["start"])
    for b in plan.get("beats", []):
        place(sfx, whoosh(rng, dur=0.6), b["at"] - 0.3)

    mix = reverb(music, rng, mix=0.4) * 1.4 + reverb(sfx, rng, seconds=1.4, mix=0.15) * 0.7
    peak = np.abs(mix).max() or 1
    return mix / peak * 0.7


def main():
    plan = json.load(open(sys.argv[1]))
    audio = compose(plan)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    with wave.open(sys.argv[2], "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main()
