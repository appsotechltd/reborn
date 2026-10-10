// The shape of a realistic-film plan: a voice-over script plus a shot list a
// text-to-video model can render one shot at a time.
import { z } from "zod";

export const Shot = z.object({
  id: z.string().describe("s01, s02, ..."),
  seconds: z.number().int().min(4).max(8).describe("Length on screen; video models render 4-8 s clips"),
  framing: z.string().describe("e.g. wide establishing shot, medium close-up, overhead"),
  camera: z.string().describe("Camera movement, e.g. slow push-in, static, handheld follow"),
  prompt: z.string().describe("Self-contained visual description for the video model: subject, action, setting, light, lens, mood. No text, logos or real people."),
  narration: z.string().describe("Voice-over spoken over this shot, in our own words; empty for silence"),
});

export const FilmPlan = z.object({
  card_id: z.string(),
  logline: z.string().describe("One sentence: what the film dramatises"),
  style: z.string().describe("Shared look for every shot so clips cut together: era, palette, lens, grade"),
  negative_prompt: z.string().describe("What every shot must avoid"),
  shots: z.array(Shot).min(4).max(10),
});

/** Checks rules the model can get wrong; returns a list of problems. */
export function checkPlan(plan, card) {
  const problems = [];
  if (plan.card_id !== card.id) problems.push(`card_id ${plan.card_id} != ${card.id}`);
  const total = plan.shots.reduce((n, s) => n + s.seconds, 0);
  if (total < 25 || total > 75) problems.push(`total length ${total}s is outside 25-75s`);
  const ids = new Set();
  for (const s of plan.shots) {
    if (ids.has(s.id)) problems.push(`duplicate shot id ${s.id}`);
    ids.add(s.id);
    const words = s.narration.trim() ? s.narration.trim().split(/\s+/).length : 0;
    if (words / s.seconds > 3.2) problems.push(`${s.id}: ${words} words won't fit in ${s.seconds}s`);
  }
  return problems;
}
