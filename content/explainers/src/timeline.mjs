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
export function buildTimeline({ card, scenes, audio, fps = 30, captionMax = 9 }) {
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
      for (const p of phrases(s.narration, captionMax)) {
        const len = (wordCount(p) / words) * speech;
        captions.push({ start: round(c), end: round(c + len), text: p });
        c += len;
      }
    }
    // Beats change the picture partway through a scene, on a given word of the narration.
    const spoken = (s.narration || "").split(/\s+/).filter(Boolean).map((w) => w.toLowerCase().replace(/[^a-z0-9']/g, ""));
    const beats = (s.params?.beats || []).map((b) => {
      let at = b.at ?? 0;
      if (b.word) {
        const w = spoken.indexOf(b.word.toLowerCase());
        if (w < 0) throw new Error(`beat word "${b.word}" is not in the narration of scene ${i} (${s.type})`);
        at = LEAD_IN + (w / Math.max(1, words)) * speech;
      }
      return { ...b, start: round(start + at) };
    });
    return { type: s.type, cut: Boolean(s.cut), params: s.params || {}, narration: s.narration || "", start: round(start), duration: round(duration),
      speechStart: round(start + LEAD_IN), captions, beats };
  });
  return { fps, width: 540, height: 960, scale: 2, card, scenes: laid, duration: round(t) };
}

const round = (v) => Math.round(v * 1000) / 1000;
