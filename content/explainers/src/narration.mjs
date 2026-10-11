// Narration: turns each scene's voice-over line into audio, in one of the approved voices
// (src/voices.mjs). Two engines run them, both free and local:
// - kokoro: Kokoro-82M (Apache-2.0). Install it with tools/setup-kokoro.sh.
// - chatterbox: Chatterbox (MIT), more expressive and slower; its voices are copies of
//   Kokoro voices. Install it with tools/setup-chatterbox.sh.
// A provider is { name, voice, synthesize(text) -> Buffer (mp3) }.
// With --voice none the video renders silent, and timings come from reading speed instead of the audio.
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { existsSync } from "node:fs";
import path from "node:path";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { ROOT } from "./library.mjs";
import { approvedVoice, referenceClip, CHATTERBOX_SETTINGS, DEFAULT_VOICE } from "./voices.mjs";

const run = promisify(execFile);

export const KOKORO_DIR = process.env.KOKORO_DIR || path.join(ROOT, ".cache", "kokoro");

export function kokoro({
  dir = KOKORO_DIR,
  voice = "af_heart",
  speed = Number(process.env.KOKORO_SPEED || 0.95),
} = {}) {
  const python = path.join(dir, "venv", "bin", "python");
  const model = path.join(dir, "kokoro-v1.0.onnx");
  const voices = path.join(dir, "voices-v1.0.bin");
  if (![python, model, voices].every(existsSync)) return null;
  const script = path.join(ROOT, "tools", "kokoro_tts.py");
  const wav = (text, out) => new Promise((resolve, reject) => {
    const p = spawn(python, [script, model, voices, voice, String(speed)], { stdio: ["pipe", "ignore", "pipe"] });
    let err = "";
    p.stderr.on("data", (d) => (err += d));
    p.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`kokoro exited ${code}: ${err.slice(-400)}`))));
    p.stdin.end(JSON.stringify({ text, out }) + "\n");
  });
  return {
    name: "kokoro",
    voice: `kokoro-82m/${voice}@${speed}`,
    wav,
    async synthesize(text) {
      const tmp = await mkdtemp(path.join(tmpdir(), "kokoro-"));
      try {
        const file = path.join(tmp, "line.wav");
        await wav(text, file);
        const mp3 = path.join(tmp, "line.mp3");
        await run("ffmpeg", ["-v", "error", "-y", "-i", file, "-c:a", "libmp3lame", "-b:a", "128k", mp3]);
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
  exaggeration = CHATTERBOX_SETTINGS.exaggeration,
  cfg = CHATTERBOX_SETTINGS.cfg,
  reference, // a wav to clone, or an async function returning one
  label = "default",
} = {}) {
  const python = path.join(dir, "venv", "bin", "python");
  if (!existsSync(python)) return null;
  const script = path.join(ROOT, "tools", "chatterbox_tts.py");
  return {
    name: "chatterbox",
    voice: `chatterbox/${label}@${exaggeration}/${cfg}`,
    async synthesize(text) {
      const tmp = await mkdtemp(path.join(tmpdir(), "chatterbox-"));
      try {
        const wav = path.join(tmp, "line.wav");
        const ref = typeof reference === "function" ? await reference() : reference || "";
        await new Promise((resolve, reject) => {
          const p = spawn(python, [script, String(exaggeration), String(cfg), ref], { stdio: ["pipe", "ignore", "pipe"] });
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
 * The provider for an approved voice name (--voice, a script's "voice", or NARRATION_VOICE);
 * "none" means silent. Throws for a voice that isn't approved or an engine that isn't installed.
 */
export function narrator(name = process.env.NARRATION_VOICE || DEFAULT_VOICE) {
  if (name === "none") return null;
  const v = approvedVoice(name);
  const k = kokoro({ voice: v.kokoroVoice });
  if (!k) throw new Error(`Kokoro is not installed in ${KOKORO_DIR}: run tools/setup-kokoro.sh`);
  if (v.engine === "kokoro") return { ...k, name: v.name };
  const c = chatterbox({ label: v.name, reference: () => referenceClip(v.kokoroVoice, (text, file) => k.wav(text, file)) });
  if (!c) throw new Error(`Chatterbox is not installed in ${CHATTERBOX_DIR}: run tools/setup-chatterbox.sh`);
  return { ...c, name: v.name };
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

