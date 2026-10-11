// Still images for the "photo" look: each shot is an AI image the renderer slowly moves through.
//
// A scene or beat asks for one with `image: { prompt }` (or `image: { file }` for an image on disk).
// Images are generated once and cached in .cache/images by prompt, so re-renders cost nothing.
// Google Imagen through the Gemini API (GEMINI_API_KEY) is the default; check the current model
// name and price in Google's docs before a large run (about $0.02 per image on Imagen 4 Fast).
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT } from "./library.mjs";

const BASE = "https://generativelanguage.googleapis.com/v1beta";
const CACHE = path.join(ROOT, ".cache", "images");

// Added to every prompt so a video's shots read as one film.
export const STYLE = "Cinematic still, photorealistic, dramatic low-key lighting, deep shadows, rich warm and teal tones, " +
  "shallow depth of field, fine film grain, vertical 9:16 composition with space in the lower third. " +
  "No text, no letters, no logos, no watermarks.";

export function imagen({ apiKey = process.env.GEMINI_API_KEY, model = process.env.IMAGEN_MODEL || "imagen-4.0-fast-generate-001" } = {}) {
  if (!apiKey) return null;
  return {
    name: "imagen",
    model,
    async generate(prompt) {
      const res = await fetch(`${BASE}/models/${model}:predict`, {
        method: "POST",
        headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
        body: JSON.stringify({ instances: [{ prompt }], parameters: { sampleCount: 1, aspectRatio: "9:16", personGeneration: "allow_adult" } }),
      });
      if (!res.ok) throw new Error(`Imagen ${res.status}: ${(await res.text()).slice(0, 400)}`);
      const b64 = (await res.json()).predictions?.[0]?.bytesBase64Encoded;
      if (!b64) throw new Error(`Imagen returned no image for "${prompt.slice(0, 80)}" (it may have been filtered)`);
      return Buffer.from(b64, "base64");
    },
  };
}

/** Every image request in the scenes, including beats. */
function requests(scenes) {
  return scenes.flatMap((s) => [s.params?.image, ...(s.params?.beats || []).map((b) => b.image)]).filter(Boolean);
}

/**
 * Resolves each `image` to a file URL the renderer can load (`image.src`), generating missing ones.
 * Returns how many were generated. Throws if an image is missing and no provider is configured.
 */
export async function resolveImages(scenes, { provider = imagen(), style = STYLE } = {}) {
  await mkdir(CACHE, { recursive: true });
  let generated = 0;
  for (const img of requests(scenes)) {
    if (img.file) { img.src = pathToFileURL(path.resolve(ROOT, img.file)).href; continue; }
    const prompt = `${img.prompt} ${style}`;
    const file = path.join(CACHE, `${createHash("sha256").update(prompt).digest("hex").slice(0, 20)}.png`);
    if (!existsSync(file)) {
      if (!provider) throw new Error("an image needs generating but GEMINI_API_KEY is not set");
      await writeFile(file, await provider.generate(prompt));
      generated++;
      console.log(`image ${generated}: ${img.prompt.slice(0, 70)}`);
    }
    img.src = pathToFileURL(file).href;
  }
  return generated;
}
