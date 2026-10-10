export const BODY_MIN_WORDS = 25;
export const BODY_MAX_WORDS = 160;

/** Count words the way the content validator does: whitespace-separated tokens. */
export function countWords(text: string): number {
  const trimmed = text.trim();
  return trimmed ? trimmed.split(/\s+/).length : 0;
}

export type WordCountState = "empty" | "short" | "ok" | "long";

export function wordCountState(
  count: number,
  min = BODY_MIN_WORDS,
  max = BODY_MAX_WORDS,
): WordCountState {
  if (count === 0) return "empty";
  if (count < min) return "short";
  if (count > max) return "long";
  return "ok";
}
