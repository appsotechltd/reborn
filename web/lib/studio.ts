import type { Audience, Card, ImageStyle, StudioRate } from "./types";

// Member cards and the card studio: labels, unit prices worked out the way the server does
// (backend/internal/rebornai/studio.go), and the timing of the illustrated video player.

export const AUDIENCES: { id: Audience; label: string; hint: string }[] = [
  { id: "everyone", label: "Everyone", hint: "In timelines and on your page" },
  { id: "followers", label: "Followers", hint: "People who follow you" },
  { id: "subscribers", label: "Subscribers", hint: "People who pay to subscribe to you" },
  { id: "private", label: "Only me", hint: "Nobody else sees it" },
];

/** The badge on a member's own card: its audience, or Hidden once reports took it down. */
export function visibilityLabel(visibility: string | undefined | null): string {
  if (visibility === "hidden") return "Hidden";
  return AUDIENCES.find((a) => a.id === visibility)?.label ?? "Everyone";
}

/** Whether an id could be a member's card: a slug, five random characters, then "--01" (the API's memberCardID). */
export function looksLikeMemberCard(id: string): boolean {
  return /-[a-z0-9]{5}--01$/.test(id);
}

export const IMAGE_STYLES: { id: ImageStyle; label: string; units: number }[] = [
  { id: "sketch", label: "Sketch", units: 2 },
  { id: "illustration", label: "Illustration", units: 4 },
  { id: "picture", label: "Photo-like", units: 12 },
];

/** Words of a card's audio: the title, the body and "Apply it." with the tip. */
export function spokenWords(card: Pick<Card, "title" | "body" | "apply_it">): number {
  let text = `${card.title}.\n\n${card.body}`;
  if (card.apply_it?.trim()) text += `\n\nApply it. ${card.apply_it}`;
  return text.split(/\s+/).filter(Boolean).length;
}

/** 1 unit per started 50 words, at least 1. */
export function audioUnits(card: Pick<Card, "title" | "body" | "apply_it">): number {
  return Math.max(1, Math.ceil(spokenWords(card) / 50));
}

/** Units for a picture style, from the studio's rates when loaded. */
export function imageUnits(style: ImageStyle, rates?: StudioRate[] | null): number {
  return rates?.find((r) => r.kind === style)?.units ?? IMAGE_STYLES.find((s) => s.id === style)?.units ?? 0;
}

/** A unit to plan the scenes, an illustration per scene, and the narration. */
export function videoUnits(
  card: Pick<Card, "title" | "body" | "apply_it">,
  scenes = 4,
  rates?: StudioRate[] | null,
): number {
  return 1 + scenes * imageUnits("illustration", rates) + audioUnits(card);
}

/** "about 12 videos, 62 illustrations or 83 one-minute audios" for a month's units. */
export function monthlyBuys(monthly: number, rates: StudioRate[]): string {
  const per = (kind: string) => rates.find((r) => r.kind === kind)?.units ?? 0;
  const n = (units: number) => (units > 0 ? Math.floor(monthly / units) : 0);
  return `about ${n(per("video"))} videos, ${n(per("illustration"))} illustrations or ${n(per("audio"))} one-minute audios`;
}

// --- The illustrated video: each scene gets an equal share of the narration ---------

/** How long each scene cross-fades into the next, in seconds. */
export const CROSSFADE_S = 0.8;

/** The scene showing at time t (seconds). */
export function sceneAt(t: number, total: number, count: number): number {
  if (count <= 1 || total <= 0) return 0;
  return Math.min(count - 1, Math.max(0, Math.floor(t / (total / count))));
}

/**
 * Opacity of every scene at time t. Later scenes sit above earlier ones, so each one fades in
 * over the CROSSFADE_S before its turn and then simply covers the one below it.
 */
export function sceneOpacities(t: number, total: number, count: number, fade = CROSSFADE_S): number[] {
  const d = count > 0 && total > 0 ? total / count : 0;
  const f = Math.min(fade, d / 2);
  return Array.from({ length: count }, (_, i) => {
    if (i === 0) return 1;
    if (f <= 0) return t >= i * d ? 1 : 0;
    return Math.max(0, Math.min(1, (t - (i * d - f)) / f));
  });
}

/** How far through its time on screen (from the start of its fade-in) scene i is, 0..1. */
export function sceneProgress(i: number, t: number, total: number, count: number, fade = CROSSFADE_S): number {
  if (count <= 0 || total <= 0) return 0;
  const d = total / count;
  const f = i === 0 ? 0 : Math.min(fade, d / 2);
  const start = i * d - f;
  // On screen until the next scene has fully covered it, at the end of its share.
  return Math.max(0, Math.min(1, (t - start) / (d + f)));
}

/** The slow Ken Burns drift for scene i at progress p: a gentle zoom with a pan that changes direction each scene. */
export function kenBurns(i: number, p: number): { scale: number; x: number; y: number } {
  const dir = [
    [1, 0.5],
    [-1, -0.5],
    [0.5, -1],
    [-0.5, 1],
  ][i % 4];
  const zoomIn = i % 2 === 0;
  const scale = zoomIn ? 1.04 + 0.1 * p : 1.14 - 0.1 * p;
  // Percent of the frame, kept inside what the zoom leaves room for.
  const x = dir[0] * (p - 0.5) * 3;
  const y = dir[1] * (p - 0.5) * 3;
  return { scale, x, y };
}

/** The duration to time scenes by: the audio's real length once known, else what the card says. */
export function videoDuration(audioDuration: number | null | undefined, cardDuration: number): number {
  return audioDuration && Number.isFinite(audioDuration) && audioDuration > 0 ? audioDuration : Math.max(0, cardDuration);
}
