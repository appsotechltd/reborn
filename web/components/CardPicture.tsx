import { mediaUrl } from "@/lib/config";
import type { CardImage } from "@/lib/types";

const TYPE_LABEL: Record<string, string> = { illustration: "Illustration", "3d": "3D", chart: "Chart" };

/** True when a chart only pictures an idea rather than plotting measured figures. */
export function isConceptChart(image: CardImage): boolean {
  return image.type === "chart" && image.basis === "illustration";
}

/** "Image: caption", plus the concept note for charts that don't show real data. */
export function imageCaption(image: CardImage): string {
  return `Image: ${image.caption}${isConceptChart(image) ? " · A concept, not measured data" : ""}`;
}

/**
 * The card's picture, 3:2 at the top of the full card, with "Image: caption" under it. It keeps its dark backdrop in both themes
 * (the pictures are made for it), with a small badge saying what kind of picture it is.
 */
export function CardPicture({ image, className = "" }: { image: CardImage; className?: string }) {
  const label = TYPE_LABEL[image.type] ?? "Image";
  return (
    <figure className={`mb-6 ${className}`} data-testid="card-image">
      <div className="relative aspect-[3/2] overflow-hidden rounded-inset bg-[#14110e]">
        {/* eslint-disable-next-line @next/next/no-img-element -- media comes from R2, not next/image's optimiser */}
        <img
          src={mediaUrl(image.url)}
          alt={image.caption}
          loading="lazy"
          decoding="async"
          className="size-full object-cover"
        />
        <span
          aria-hidden="true"
          className="absolute left-2.5 top-2.5 rounded-full bg-[rgba(20,17,14,0.72)] px-2.5 py-0.5 text-xs font-semibold text-[#e9a23b]"
        >
          {label}
        </span>
      </div>
      <figcaption className="mt-2 text-xs text-muted" data-testid="card-image-caption">
        {imageCaption(image)}
      </figcaption>
    </figure>
  );
}
