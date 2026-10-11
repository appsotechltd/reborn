#!/usr/bin/env node
// Writes a realistic-film plan (voice-over script + shot list) for idea cards with Claude.
//
//   ANTHROPIC_API_KEY=... node film/plan.mjs aesops-fables--07 [more ids]
//
// Plans land in film/plans/<card-id>.json for a person to review and edit
// before anything is sent to a (paid) video model.
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { ROOT, loadCard } from "../src/library.mjs";
import { FilmPlan, checkPlan } from "./schema.mjs";

const MODEL = process.env.FILM_PLAN_MODEL || "claude-opus-5-5";

const SYSTEM = `You write short, realistic films that dramatise one idea card from Reborn, a microlearning app.
Each film is 30-60 seconds, vertical 9:16, made of 4-10 shots that a text-to-video model renders one at a time.

Rules:
- Dramatise the idea with original scenes and characters. Never depict real, identifiable people, book covers, logos, brand names or copyrighted characters. Historical authors may appear only as anonymous figures in period dress, seen from behind or at a distance.
- Prompts contain no on-screen text; captions and credits are added later.
- Each shot prompt must stand alone (the model has no memory between shots): repeat the character's look, wardrobe, setting and the shared style in every prompt so the clips cut together.
- Narration is in plain, warm English, faithful to the card, about 2.5 words per second of shot length. Do not quote the source unless its licence allows quotes (the user message says).
- Health cards: show calm, everyday, non-clinical scenes; never imply diagnosis or treatment; the last shot leaves room for the "not medical advice" note.
- The final shot is a quiet beat with no narration, for the end card.`;

async function planFor(client, cardId) {
  const card = await loadCard(cardId);
  const brief = {
    id: card.id, title: card.title, body: card.body, apply_it: card.applyIt, topic: card.topicName,
    source: `${card.sourceTitle} by ${card.authors.join(", ")}`, licence: card.licenceName,
    quotes_allowed: card.licence !== "original-summary", quote: card.quote, health: card.health,
  };
  const res = await client.beta.messages.parse({
    model: MODEL,
    max_tokens: 16000,
    output_config: { effort: "high", format: betaZodOutputFormat(FilmPlan) },
    // Retry a safety decline on Anthropic's recommended fallback model.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: SYSTEM,
    messages: [{ role: "user", content: `Write the film plan for this card:\n\n${JSON.stringify(brief, null, 2)}` }],
  });
  if (res.stop_reason === "refusal") throw new Error(`${cardId}: declined (${res.stop_details?.category ?? "no category"})`);
  const plan = res.parsed_output;
  if (!plan) throw new Error(`${cardId}: no plan in the response (stop_reason ${res.stop_reason})`);
  const problems = checkPlan(plan, card);
  const file = path.join(ROOT, "film", "plans", `${cardId}.json`);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(plan, null, 2) + "\n");
  console.log(`${cardId}: ${plan.shots.length} shots -> ${path.relative(process.cwd(), file)}`);
  for (const p of problems) console.warn(`  check: ${p}`);
}

const ids = process.argv.slice(2);
if (!ids.length) {
  console.error("usage: node film/plan.mjs <card-id> [...]");
  process.exit(2);
}
const client = new Anthropic();
for (const id of ids) await planFor(client, id);
