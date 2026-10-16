import Link from "next/link";
import { mediaUrl } from "@/lib/config";
import type { Card, PostImage } from "@/lib/types";

/** True when the feed shows this card as an image post: it has one and no video to play instead. */
export function isImagePost(card: Card): card is Card & { post_image: PostImage } {
  return !!card.post_image?.url && !card.explainer && !card.video?.scenes?.length;
}

/**
 * A card's image post in the feed: the designed picture (title, category and book already set in it),
 * linking to the card's page, with "Read the idea" under it. On phones it shrinks to fit its slide.
 */
export function ImagePost({ card, href, snap = false }: { card: Card & { post_image: PostImage }; href: string; snap?: boolean }) {
  const img = card.post_image;
  return (
    <figure className={`mx-auto max-w-read ${snap ? "max-md:flex max-md:min-h-0 max-md:flex-1 max-md:flex-col" : ""}`} data-testid="image-post">
      <Link
        href={href}
        className={`block overflow-hidden rounded-card bg-[#14110e] ${snap ? "max-md:flex max-md:min-h-0 max-md:flex-1 max-md:items-center max-md:justify-center" : ""}`}
      >
        {/* eslint-disable-next-line @next/next/no-img-element -- media comes from R2, not next/image's optimiser */}
        <img
          src={mediaUrl(img.url)}
          alt={`${card.title}. ${img.alt}`.trim()}
          width={img.width}
          height={img.height}
          loading="lazy"
          decoding="async"
          className={`h-auto w-full ${snap ? "max-md:max-h-full max-md:w-auto max-md:object-contain" : ""}`}
        />
      </Link>
      <figcaption className="mt-3 flex items-center justify-between gap-3 text-sm max-md:mt-2">
        <Link href={href} aria-label={`Read the idea: ${card.title}`} className="font-semibold text-accent-text hover:underline">
          Read the idea
        </Link>
      </figcaption>
    </figure>
  );
}
