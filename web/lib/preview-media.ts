import type { Card, CardImage } from "./types";

/** A picture to show in a link preview, with its shape when known. */
export interface PreviewMedia {
  /** Absolute, or a path relative to the API base URL. */
  url: string;
  width?: number;
  height?: number;
}

/**
 * The picture a shared idea shows in its link preview: the wide video poster (the video
 * og:video plays), then the card's picture, then its image post, then the tall poster.
 * Null for a text-only card, which keeps the drawn text preview.
 */
export function cardPreviewMedia(card: Card): PreviewMedia | null {
  const e = card.explainer;
  if (e?.landscape?.poster_url) return { url: e.landscape.poster_url, width: e.landscape.width, height: e.landscape.height };
  if (card.image?.url) return { url: card.image.url };
  if (card.post_image?.url) return { url: card.post_image.url, width: card.post_image.width, height: card.post_image.height };
  if (e?.poster_url) return { url: e.poster_url, width: e.width, height: e.height };
  return null;
}

/** A guide's or subject's cover as preview media. */
export function coverPreviewMedia(cover?: CardImage | null): PreviewMedia | null {
  return cover?.url ? { url: cover.url } : null;
}
