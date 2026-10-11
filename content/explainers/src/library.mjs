// Reads idea cards from content/library so every video shows the same title,
// credit, licence and health note as the card itself.
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const LIBRARY = path.resolve(ROOT, "../library");

// Mirrors backend/internal/content/types.go.
export const HEALTH_DISCLAIMER =
  "This is general information, not medical advice. Talk to a qualified health professional about your own situation.";

export const TOPIC_NAMES = {
  business: "Business",
  psychology: "Psychology",
  health: "Health & Wellness",
  "emotional-intelligence": "Emotional Intelligence",
  "personal-development": "Personal Development",
  productivity: "Productivity & Career",
  money: "Money",
  relationships: "Relationships",
  mindfulness: "Mindfulness & Philosophy",
};

export const LICENCE_NAMES = {
  "public-domain": "Public domain",
  "us-gov-public-domain": "US Government work, public domain",
  "cc-by-4.0": "CC BY 4.0",
  "cc-by-3.0": "CC BY 3.0",
  "cc-by-sa-4.0": "CC BY-SA 4.0",
  "cc0-1.0": "CC0 1.0",
  "ogl-3.0": "Open Government Licence v3.0",
  "original-summary": "Original summary, linked to the source",
};

/** Returns the card with the fields a video needs, or throws if it does not exist. */
export async function loadCard(cardId) {
  const sourceId = cardId.split("--")[0];
  const file = path.join(LIBRARY, `${sourceId}.json`);
  const lib = JSON.parse(await readFile(file, "utf8"));
  const c = lib.cards.find((x) => x.id === cardId);
  if (!c) throw new Error(`card ${cardId} not found in ${file}`);
  const s = lib.source;
  const health = Boolean(c.health) || c.topic === "health";
  return {
    id: c.id,
    title: c.title,
    body: c.body,
    quote: s.licence === "original-summary" ? null : c.quote ?? null,
    applyIt: c.apply_it,
    topic: c.topic,
    topicName: TOPIC_NAMES[c.topic] ?? c.topic,
    health,
    disclaimer: health ? HEALTH_DISCLAIMER : null,
    sourceId: s.id,
    sourceTitle: s.title,
    sourceUrl: s.url,
    authors: s.authors,
    licence: s.licence,
    licenceName: LICENCE_NAMES[s.licence] ?? s.licence,
    credit: `Source: ${s.attribution}`,
  };
}

export async function listScripts(dir) {
  return (await readdir(dir)).filter((f) => f.endsWith(".json")).map((f) => f.replace(/\.json$/, "")).sort();
}
