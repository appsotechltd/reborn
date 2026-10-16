import type { Card } from "./types";

/** The All / Videos / Images switch: every card, only those with a video, or only those with a picture. */
export type MediaFilter = "all" | "videos" | "images";

/** A video: a rendered explainer, or a member card's illustrated video. */
export function hasVideo(card: Card): boolean {
  return !!card.explainer || !!card.video;
}

export function hasImage(card: Card): boolean {
  return !!card.image;
}

/** `media` for GET /v1/timeline; undefined for all. */
export function mediaQuery(filter: MediaFilter): "video" | "image" | undefined {
  return filter === "videos" ? "video" : filter === "images" ? "image" : undefined;
}
