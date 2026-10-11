// AI still images: shots for the "photo" look, and stand-alone art such as card and quote images.
//
// A scene or beat asks for one with `image: { prompt }`, `image: { prompt, text }` for an image
// with words in it (a quote image), or `image: { file }` for an image on disk. Images are made once
// and cached in .cache/images by provider + prompt, so re-renders cost nothing.
//
// Providers, each read from its own key:
// - openai: OpenAI's image model (OPENAI_API_KEY, OPENAI_IMAGE_MODEL). Default for photoreal shots.
// - ideogram: Ideogram 3.0 (IDEOGRAM_API_KEY). Default for images with text, which it spells best.
// - imagen: Google Imagen through the Gemini API (GEMINI_API_KEY, IMAGEN_MODEL).
// IMAGE_PROVIDER (or --image-provider, or `provider` on one image) forces one; "auto" (the default)
// picks by kind and falls back to whichever key is set. Check each provider's current model names
// and prices before a large run.
//
// Stand-alone use, e.g. card art or a quote image:
//   node src/images.mjs "A candle burning low on a desk" --out art.png
//   node src/images.mjs "A dark stone wall" --text "Life is long enough" --out quote.png
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { copyFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ROOT } from "./library.mjs";

const CACHE = path.join(ROOT, ".cache", "images");

// Added to every photo prompt so a video's shots read as one film.
export const STYLE = "Cinematic still, photorealistic, dramatic low-key lighting, deep shadows, rich warm and teal tones, " +
  "shallow depth of field, fine film grain, vertical 9:16 composition with space in the lower third. " +
  "No text, no letters, no logos, no watermarks.";

// Added to images that carry words: the words must be exact and the only text.
export const TEXT_STYLE = "Elegant, dark, cinematic typographic image, vertical 9:16. The only text in the image is the quoted " +
  "words, spelled exactly, in a refined serif, large and legible, with generous margins. No other text, no logos, no watermarks.";

async function failure(name, res) {
  return new Error(`${name} ${res.status}: ${(await res.text()).slice(0, 400)}`);
}

export function imagen({ apiKey = process.env.GEMINI_API_KEY, model = process.env.IMAGEN_MODEL || "imagen-4.0-fast-generate-001", fetch = globalThis.fetch } = {}) {
  if (!apiKey) return null;
  return {
    name: "imagen",
    model,
    async generate(prompt) {
      const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:predict`, {
        method: "POST",
        headers: { "x-goog-api-key": apiKey, "content-type": "application/json" },
        body: JSON.stringify({ instances: [{ prompt }], parameters: { sampleCount: 1, aspectRatio: "9:16", personGeneration: "allow_adult" } }),
      });
      if (!res.ok) throw await failure("Imagen", res);
      const b64 = (await res.json()).predictions?.[0]?.bytesBase64Encoded;
      if (!b64) throw new Error(`Imagen returned no image for "${prompt.slice(0, 80)}" (it may have been filtered)`);
      return Buffer.from(b64, "base64");
    },
  };
}

export function openai({ apiKey = process.env.OPENAI_API_KEY, model = process.env.OPENAI_IMAGE_MODEL || "gpt-image-1", quality = process.env.OPENAI_IMAGE_QUALITY || "medium", fetch = globalThis.fetch } = {}) {
  if (!apiKey) return null;
  return {
    name: "openai",
    model,
    async generate(prompt) {
      const res = await fetch("https://api.openai.com/v1/images/generations", {
        method: "POST",
        headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
        // 1024x1536 is the model's portrait size; the renderer crops it to 9:16.
        body: JSON.stringify({ model, prompt, size: "1024x1536", quality, n: 1 }),
      });
      if (!res.ok) throw await failure("OpenAI images", res);
      const b64 = (await res.json()).data?.[0]?.b64_json;
      if (!b64) throw new Error(`OpenAI returned no image for "${prompt.slice(0, 80)}"`);
      return Buffer.from(b64, "base64");
    },
  };
}

export function ideogram({ apiKey = process.env.IDEOGRAM_API_KEY, speed = process.env.IDEOGRAM_SPEED || "QUALITY", fetch = globalThis.fetch } = {}) {
  if (!apiKey) return null;
  return {
    name: "ideogram",
    model: `ideogram-v3/${speed.toLowerCase()}`,
    async generate(prompt) {
      const form = new FormData();
      form.set("prompt", prompt);
      form.set("aspect_ratio", "9x16");
      form.set("rendering_speed", speed);
      form.set("magic_prompt", "OFF"); // keep our wording, so quoted text stays exact
      const res = await fetch("https://api.ideogram.ai/v1/ideogram-v3/generate", { method: "POST", headers: { "Api-Key": apiKey }, body: form });
      if (!res.ok) throw await failure("Ideogram", res);
      const url = (await res.json()).data?.[0]?.url;
      if (!url) throw new Error(`Ideogram returned no image for "${prompt.slice(0, 80)}"`);
      const img = await fetch(url); // a short-lived link, so download it straight away
      if (!img.ok) throw await failure("Ideogram download", img);
      return Buffer.from(await img.arrayBuffer());
    },
  };
}

const FACTORIES = { openai, ideogram, imagen };
// Who goes first for each kind of image when no provider is forced.
const PREFERENCE = { photo: ["openai", "imagen", "ideogram"], text: ["ideogram", "openai", "imagen"] };

/** Photo shots go to OpenAI, images with words to Ideogram, each falling back to whatever key is set. */
export function pickProvider(kind = "photo", { name = process.env.IMAGE_PROVIDER || "auto", make = FACTORIES } = {}) {
  if (name !== "auto") {
    if (!make[name]) throw new Error(`unknown image provider "${name}" (known: auto, ${Object.keys(FACTORIES).join(", ")})`);
    const p = make[name]();
    if (!p) throw new Error(`image provider "${name}" has no API key set`);
    return p;
  }
  for (const n of PREFERENCE[kind]) {
    const p = make[n]();
    if (p) return p;
  }
  return null;
}

/** The full prompt sent for an image request. */
export function fullPrompt(img) {
  return img.text ? `${img.prompt} The image shows the words "${img.text}". ${TEXT_STYLE}` : `${img.prompt} ${STYLE}`;
}

/** Every image request in the scenes, including beats. */
function requests(scenes) {
  return scenes.flatMap((s) => [s.params?.image, ...(s.params?.beats || []).map((b) => b.image)]).filter(Boolean);
}

/** Makes (or reuses from the cache) one image; returns its file path. */
export async function makeImage(img, { provider, providerName, cache = CACHE } = {}) {
  const kind = img.text ? "text" : "photo";
  const p = provider ?? pickProvider(kind, { name: img.provider || providerName });
  if (!p) throw new Error("an image needs generating but no image key is set (OPENAI_API_KEY, IDEOGRAM_API_KEY or GEMINI_API_KEY)");
  const prompt = fullPrompt(img);
  const file = path.join(cache, `${p.name}-${createHash("sha256").update(`${p.model}\n${prompt}`).digest("hex").slice(0, 20)}.png`);
  if (!existsSync(file)) {
    await mkdir(cache, { recursive: true });
    await writeFile(file, await p.generate(prompt));
    console.log(`image (${p.name}): ${img.prompt.slice(0, 70)}`);
  }
  return file;
}

/**
 * Resolves each `image` to a file URL the renderer can load (`image.src`), generating missing ones.
 * `provider` forces one provider object; `providerName` forces one by name ("auto" picks per image).
 */
export async function resolveImages(scenes, { provider, providerName } = {}) {
  for (const img of requests(scenes)) {
    const file = img.file ? path.resolve(ROOT, img.file) : await makeImage(img, { provider, providerName });
    img.src = pathToFileURL(file).href;
  }
}

async function main() {
  const a = process.argv.slice(2);
  const img = {};
  let out = "image.png";
  for (let i = 0; i < a.length; i++) {
    if (a[i] === "--text") img.text = a[++i];
    else if (a[i] === "--provider") img.provider = a[++i];
    else if (a[i] === "--out") out = a[++i];
    else img.prompt = a[i];
  }
  if (!img.prompt) throw new Error('usage: node src/images.mjs "<prompt>" [--text "<words>"] [--provider openai|ideogram|imagen] [--out file.png]');
  await copyFile(await makeImage(img), out);
  console.log(out);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(e.message); process.exit(1); });
