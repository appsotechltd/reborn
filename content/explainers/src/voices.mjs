// The narration voices Reborn is allowed to use. The product owner picked these on
// 2026-10-11 from every Kokoro and Chatterbox option; anything else is rejected.
//
// A script picks one with "voice": "<name>" (or `--voice <name>`, or NARRATION_VOICE).
// Pick whichever suits the card; DEFAULT_VOICE is used when none is set.
//
// The Chatterbox voices are copies of Kokoro voices: Chatterbox clones a short reference
// clip, which is made here with Kokoro (our own Apache-2.0 output), so no recording of a
// real person is involved and nothing needs downloading or committing.
import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "./library.mjs";

export const DEFAULT_VOICE = "heart";

// Kokoro voice ids by name: accent and gender are in the id (a = American, b = British; f/m).
const KOKORO = {
  heart: "af_heart", bella: "af_bella", emma: "bf_emma", michael: "am_michael", george: "bm_george",
  sarah: "af_sarah", alloy: "af_alloy", nova: "af_nova", adam: "am_adam", echo: "am_echo",
  eric: "am_eric", liam: "am_liam",
};

// Chatterbox copies, by the Kokoro voice they clone. These settings are the ones that were approved.
const CHATTERBOX = { "heart-chatterbox": "af_heart", "bella-chatterbox": "af_bella", "george-chatterbox": "bm_george" };
export const CHATTERBOX_SETTINGS = { exaggeration: 0.5, cfg: 0.5 };

// The line the reference clips (and the approval samples) read.
export const REFERENCE_LINE = "It is not that we have a short time to live, but that we waste a great deal of it. " +
  "Life is long enough, if it is well invested.";

export const VOICES = [...Object.keys(KOKORO), ...Object.keys(CHATTERBOX)];

/** Looks up an approved voice: { engine: "kokoro" | "chatterbox", kokoroVoice }. Throws for anything else. */
export function approvedVoice(name = DEFAULT_VOICE) {
  const key = String(name).toLowerCase();
  if (KOKORO[key]) return { name: key, engine: "kokoro", kokoroVoice: KOKORO[key] };
  if (CHATTERBOX[key]) return { name: key, engine: "chatterbox", kokoroVoice: CHATTERBOX[key] };
  throw new Error(`"${name}" is not an approved voice. Approved: ${VOICES.join(", ")}`);
}

/** Where the Kokoro reference clip for a Chatterbox copy lives; `make` writes it if missing. */
export async function referenceClip(kokoroVoice, make) {
  const file = path.join(ROOT, ".cache", "voices", `${kokoroVoice}-reference.wav`);
  if (!existsSync(file)) {
    await mkdir(path.dirname(file), { recursive: true });
    await make(REFERENCE_LINE, file);
  }
  return file;
}
