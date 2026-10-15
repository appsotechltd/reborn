/*
 * Small helpers behind the "Candlelight refined" look, shared with the app (app/lib/src/widgets/polish.dart):
 * the generated book covers and the quote covers on feed posts.
 */

/** Spine colours for generated book covers: deep, warm and distinct, with light text on all of them. */
const COVER_COLORS: [string, string][] = [
  ["#6B2A22", "#2E1210"],
  ["#3E4A5A", "#1D242E"],
  ["#4E5B3A", "#222A18"],
  ["#6F4E7A", "#2E1F36"],
  ["#8A5A1E", "#3A240A"],
  ["#2F5A58", "#122826"],
  ["#7A3B4E", "#331520"],
  ["#4A4038", "#1F1A15"],
];

/** The same colour pair for the same book (or person) every time, as the app picks it. */
export function coverColorsFor(id: string): [string, string] {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) & 0x7fffffff;
  return COVER_COLORS[h % COVER_COLORS.length];
}

/** The first letter of a title, skipping "The", "A" and "An". */
export function titleInitial(title: string): string {
  const words = title.trim().split(/\s+/);
  const w = words.length > 1 && ["the", "a", "an"].includes(words[0].toLowerCase()) ? words[1] : words[0];
  return w ? Array.from(w)[0].toUpperCase() : "";
}

/** Initials for a person's avatar: the first letters of the first and last names. */
export function personInitials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (!words.length) return "";
  const first = Array.from(words[0])[0] ?? "";
  const last = words.length > 1 ? (Array.from(words[words.length - 1])[0] ?? "") : "";
  return (first + last).toUpperCase();
}

/** A quote's opening sentence, short enough for a post's cover. */
export function firstSentence(quote: string): string {
  const q = quote.replace(/["“”]/g, "").trim();
  const m = /^.{20,}?[.;!?](\s|$)/.exec(q);
  const s = (m?.[0] ?? q).trim();
  return s.length > 140 ? `${s.slice(0, 137).trimEnd()}…` : s;
}
