// Narration: turns each scene's voice-over line into audio.
//
// A provider is { name, voice, synthesize(text, { previousText, nextText }) -> Buffer (mp3) }.
// ElevenLabs is the default; with no key the video renders silent with burned-in
// captions, and timings come from reading speed instead of the audio.
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
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

/** Picks the provider from --voice / NARRATION_PROVIDER; null means silent. */
export function narrator(name = process.env.NARRATION_PROVIDER || "elevenlabs") {
  if (name === "none") return null;
  if (name === "elevenlabs") return elevenLabs();
  throw new Error(`unknown narration provider "${name}" (known: elevenlabs, none)`);
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

