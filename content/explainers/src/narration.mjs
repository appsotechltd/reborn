// Narration: turns each scene's voice-over line into audio.
//
// A provider is { name, voice, synthesize(text, { previousText, nextText }) -> Buffer (mp3) }.
// Two are built in:
// - kokoro: Kokoro-82M, a free open-weights voice (Apache-2.0) that runs locally.
// - chatterbox: Chatterbox (MIT), more expressive, with an emotion dial and voice cloning; slower.
//   Install it with tools/setup-kokoro.sh. This is the default when it is installed.
// - elevenlabs: paid, used instead when ELEVENLABS_API_KEY is set.
// With neither, the video renders silent with burned-in captions, and timings
// come from reading speed instead of the audio.
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { existsSync } from "node:fs";
import path from "node:path";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { ROOT } from "./library.mjs";

const run = promisify(execFile);

export function elevenLabs({
  apiKey = process.env.ELEVENLABS_API_KEY,
  voiceId = process.env.ELEVENLABS_VOICE_ID || "JBFqnCBsd6RMkjVDRZzb", // "George", a stock ElevenLabs narrator voice
  modelId = process.env.ELEVENLABS_MODEL || "eleven_multilingual_v2",
} = {}) {
  if (!apiKey) return null;
  return {
    name: "elevenlabs",
    voice: `${voiceId}/${modelId}`,
    async synthesize(text, { previousText, nextText } = {}) {
      const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`, {
        method: "POST",
        headers: { "xi-api-key": apiKey, "content-type": "application/json", accept: "audio/mpeg" },
        body: JSON.stringify({
          text,
          model_id: modelId,
          previous_text: previousText || undefined,
          next_text: nextText || undefined,
          voice_settings: { stability: 0.5, similarity_boost: 0.75, style: 0.15, use_speaker_boost: true },
        }),
      });
      if (!res.ok) throw new Error(`ElevenLabs ${res.status}: ${(await res.text()).slice(0, 300)}`);
      return Buffer.from(await res.arrayBuffer());
    },
  };
}

export const KOKORO_DIR = process.env.KOKORO_DIR || path.join(ROOT, ".cache", "kokoro");

export function kokoro({
  dir = KOKORO_DIR,
  voice = process.env.KOKORO_VOICE || "af_heart", // the highest-rated Kokoro voice; British options: bf_emma, bm_george
  speed = Number(process.env.KOKORO_SPEED || 0.95),
} = {}) {
  const python = path.join(dir, "venv", "bin", "python");
  const model = path.join(dir, "kokoro-v1.0.onnx");
  const voices = path.join(dir, "voices-v1.0.bin");
  if (![python, model, voices].every(existsSync)) return null;
  const script = path.join(ROOT, "tools", "kokoro_tts.py");
  return {
    name: "kokoro",
    voice: `kokoro-82m/${voice}@${speed}`,
    async synthesize(text) {
      const tmp = await mkdtemp(path.join(tmpdir(), "kokoro-"));
      try {
        const wav = path.join(tmp, "line.wav");
        await new Promise((resolve, reject) => {
          const p = spawn(python, [script, model, voices, voice, String(speed)], { stdio: ["pipe", "ignore", "pipe"] });
          let err = "";
          p.stderr.on("data", (d) => (err += d));
          p.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`kokoro exited ${code}: ${err.slice(-400)}`))));
          p.stdin.end(JSON.stringify({ text, out: wav }) + "\n");
        });
        const mp3 = path.join(tmp, "line.mp3");
        await run("ffmpeg", ["-v", "error", "-y", "-i", wav, "-c:a", "libmp3lame", "-b:a", "128k", mp3]);
        return await readFile(mp3);
      } finally {
        await rm(tmp, { recursive: true, force: true });
      }
    },
  };
}

export const CHATTERBOX_DIR = process.env.CHATTERBOX_DIR || path.join(ROOT, ".cache", "chatterbox");

/** Chatterbox (Resemble AI, MIT): more expressive than Kokoro, slower on a CPU. */
export function chatterbox({
  dir = CHATTERBOX_DIR,
  exaggeration = Number(process.env.CHATTERBOX_EXAGGERATION || 0.6),
  cfg = Number(process.env.CHATTERBOX_CFG || 0.35),
  reference = process.env.CHATTERBOX_REFERENCE || "",
} = {}) {
  const python = path.join(dir, "venv", "bin", "python");
  if (!existsSync(python)) return null;
  const script = path.join(ROOT, "tools", "chatterbox_tts.py");
  return {
    name: "chatterbox",
    voice: `chatterbox/${path.basename(reference) || "default"}@${exaggeration}/${cfg}`,
    async synthesize(text) {
      const tmp = await mkdtemp(path.join(tmpdir(), "chatterbox-"));
      try {
        const wav = path.join(tmp, "line.wav");
        await new Promise((resolve, reject) => {
          const p = spawn(python, [script, String(exaggeration), String(cfg), reference], { stdio: ["pipe", "ignore", "pipe"] });
          let err = "";
          p.stderr.on("data", (d) => (err += d));
          p.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`chatterbox exited ${code}: ${err.slice(-400)}`))));
          p.stdin.end(JSON.stringify({ text, out: wav }) + "\n");
        });
        const mp3 = path.join(tmp, "line.mp3");
        await run("ffmpeg", ["-v", "error", "-y", "-i", wav, "-c:a", "libmp3lame", "-b:a", "128k", mp3]);
        return await readFile(mp3);
      } finally {
        await rm(tmp, { recursive: true, force: true });
      }
    },
  };
}

/**
 * Picks the provider from --voice / NARRATION_PROVIDER; null means silent.
 * "auto" (the default) uses ElevenLabs when its key is set, else Kokoro when installed.
 */
export function narrator(name = process.env.NARRATION_PROVIDER || "auto") {
  if (name === "none") return null;
  if (name === "elevenlabs") return elevenLabs();
  if (name === "kokoro") {
    const k = kokoro();
    if (!k) throw new Error(`Kokoro is not installed in ${KOKORO_DIR}: run tools/setup-kokoro.sh`);
    return k;
  }
  if (name === "chatterbox") {
    const c = chatterbox();
    if (!c) throw new Error(`Chatterbox is not installed in ${CHATTERBOX_DIR}: run tools/setup-chatterbox.sh`);
    return c;
  }
  if (name === "auto") return elevenLabs() ?? kokoro();
  throw new Error(`unknown narration provider "${name}" (known: auto, kokoro, chatterbox, elevenlabs, none)`);
}

export async function audioSeconds(file) {
  const { stdout } = await run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]);
  return Number(stdout.trim());
}

/**
 * Synthesises every scene's narration, caching by text + voice so re-renders
 * only pay for lines that changed. Returns [{ file, seconds } | null] per scene.
 */
export async function narrate(provider, cardId, lines) {
  if (!provider) return lines.map(() => null);
  const dir = path.join(ROOT, ".cache", "audio", cardId);
  await mkdir(dir, { recursive: true });
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const text = lines[i];
    if (!text) { out.push(null); continue; }
    const hash = createHash("sha256").update(`${provider.voice}\n${text}`).digest("hex").slice(0, 16);
    const file = path.join(dir, `${String(i).padStart(2, "0")}-${hash}.mp3`);
    if (!existsSync(file)) {
      const audio = await provider.synthesize(text, { previousText: lines[i - 1], nextText: lines[i + 1] });
      await writeFile(file, audio);
    }
    out.push({ file, seconds: await audioSeconds(file) });
  }
  return out;
}

