import { BODY_MAX_WORDS, BODY_MIN_WORDS, countWords, wordCountState } from "@/lib/words";

const MESSAGES = {
  empty: (min: number, max: number) => `Aim for ${min}–${max} words (about a minute to read).`,
  short: (min: number) => `needs at least ${min}`,
  ok: () => "about a minute to read",
  long: (_min: number, max: number) => `too long, keep it to ${max}`,
} as const;

/** Live word count for the card body, matching the 25–160 word rule. */
export function WordCounter({
  text,
  id,
  min = BODY_MIN_WORDS,
  max = BODY_MAX_WORDS,
}: {
  text: string;
  id?: string;
  min?: number;
  max?: number;
}) {
  const count = countWords(text);
  const state = wordCountState(count, min, max);
  const color = state === "ok" ? "text-ok" : state === "empty" ? "text-muted" : "text-bad";
  return (
    <p id={id} className={`hint ${color}`} aria-live="polite" data-state={state}>
      {state === "empty" ? (
        MESSAGES.empty(min, max)
      ) : (
        <>
          <strong>
            {count} {count === 1 ? "word" : "words"}
          </strong>{" "}
          ({MESSAGES[state](min, max)})
        </>
      )}
    </p>
  );
}
