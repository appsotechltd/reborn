// Text-to-video providers for realistic films.
//
// A provider is:
//   { name, clipSeconds: [min, max],
//     start({ prompt, negativePrompt, seconds, aspectRatio }) -> jobId,
//     poll(jobId) -> { done: false } | { done: true, url, headers? } | { done: true, file } (throws on failure) }
// Each is inert until its key is set, so nothing is spent by accident.
import { veo } from "./veo.mjs";
import { runway } from "./runway.mjs";
import { animatic } from "./animatic.mjs";

export const PROVIDERS = { veo, runway, animatic };

export function videoProvider(name = process.env.FILM_PROVIDER || "veo") {
  const make = PROVIDERS[name];
  if (!make) throw new Error(`unknown video provider "${name}" (known: ${Object.keys(PROVIDERS).join(", ")})`);
  const p = make();
  if (!p) throw new Error(`${name} has no API key: set ${name === "veo" ? "GEMINI_API_KEY" : "RUNWAYML_API_SECRET"}`);
  return p;
}
