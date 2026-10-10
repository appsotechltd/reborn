// Lays scenes out in time and splits narration into on-screen caption phrases.

export const WORDS_PER_SECOND = 2.6; // calm narration pace, also used for silent captions
const LEAD_IN = 0.35; // pause before a scene's line starts
const TAIL = 0.9; // breathing room after it ends

export const wordCount = (s) => (s ? s.trim().split(/\s+/).length : 0);

/**
 * Splits a line into caption phrases: sentence by sentence, and a long sentence
 * into evenly sized chunks of at most `max` words, so no phrase is a lonely word.
 */
export function phrases(text, max = 9) {
  const sentences = text.trim().match(/[^.!?;:]+[.!?;:]*["”’]?/g) || [];
  const out = [];
  for (const sentence of sentences) {
    const words = sentence.trim().split(/\s+/).filter(Boolean);
    if (!words.length) continue;
    const n = Math.ceil(words.length / max);
    const size = Math.ceil(words.length / n);
    for (let i = 0; i < words.length; i += size) out.push(words.slice(i, i + size).join(" "));
  }
  // fold a one- or two-word sentence into its neighbour when they fit together
  for (let i = out.length - 1; i > 0; i--) {
    if (wordCount(out[i]) <= 2 && wordCount(out[i - 1]) + wordCount(out[i]) <= max + 2) { out[i - 1] += " " + out[i]; out.splice(i, 1); }
  }
  return out;
}

/**
 * scenes: [{ type, narration, params, min_seconds }]
 * audio:  per scene { seconds } | null (null = estimate from word count)
 */
export function buildTimeline({ card, scenes, audio, fps = 30 }) {
  let t = 0;
  const laid = scenes.map((s, i) => {
    const words = wordCount(s.narration);
    const speech = audio[i]?.seconds ?? words / WORDS_PER_SECOND;
    const duration = Math.max(s.min_seconds ?? 0, words ? LEAD_IN + speech + TAIL : 0, 2.5);
    const start = t;
    t += duration;
    // Captions share the spoken time in proportion to their word counts.
    const captions = [];
    if (words) {
      let c = start + LEAD_IN;
      for (const p of phrases(s.narration)) {
        const len = (wordCount(p) / words) * speech;
        captions.push({ start: round(c), end: round(c + len), text: p });
        c += len;
      }
    }
    return { type: s.type, cut: Boolean(s.cut), params: s.params || {}, narration: s.narration || "", start: round(start), duration: round(duration),
      speechStart: round(start + LEAD_IN), captions };
  });
  return { fps, width: 540, height: 960, scale: 2, card, scenes: laid, duration: round(t) };
}

const round = (v) => Math.round(v * 1000) / 1000;

const vttTime = (s) => {
  const ms = Math.round(s * 1000);
  const h = Math.floor(ms / 3600000), m = Math.floor((ms % 3600000) / 60000), sec = Math.floor((ms % 60000) / 1000);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}.${String(ms % 1000).padStart(3, "0")}`;
};

export function toVtt(timeline) {
  const cues = timeline.scenes.flatMap((s) => s.captions);
  return "WEBVTT\n\n" + cues.map((c, i) => `${i + 1}\n${vttTime(c.start)} --> ${vttTime(c.end)}\n${c.text}\n`).join("\n");
}
