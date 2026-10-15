import { mediaUrl } from "@/lib/config";
import { coverColorsFor, firstSentence, personInitials, titleInitial } from "@/lib/polish";
import type { Card } from "@/lib/types";

/**
 * A small typeset book cover for books with no artwork, as in the app: a warm spine colour picked
 * from the book id, with the title's initial in Fraunces. Decorative (the title is next to it).
 */
export function BookCover({ id, title, className = "h-14 w-10 text-[1.0625rem]" }: { id: string; title: string; className?: string }) {
  const [top, bottom] = coverColorsFor(id);
  return (
    <span
      aria-hidden="true"
      data-book-cover
      className={`flex shrink-0 items-end rounded-[4px] border-l-[3px] border-white/12 px-[0.45em] pb-[0.35em] font-serif font-semibold leading-none text-[#f3e4ca] shadow-[0_6px_12px_-6px_rgba(0,0,0,0.4)] ${className}`}
      style={{ background: `linear-gradient(135deg, ${top}, ${bottom})` }}
    >
      {titleInitial(title)}
    </span>
  );
}

/** A round avatar with a person's initials on their own warm colour (authors have no photos). */
export function PersonAvatar({ name, className = "size-11 text-base" }: { name: string; className?: string }) {
  const [top, bottom] = coverColorsFor(name);
  return (
    <span
      aria-hidden="true"
      data-person-avatar
      className={`grid shrink-0 place-items-center rounded-full font-serif font-semibold text-[#f3e4ca] ${className}`}
      style={{ background: `linear-gradient(135deg, ${top}, ${bottom})` }}
    >
      {personInitials(name)}
    </span>
  );
}

/**
 * The top of a phone feed post, as in the app: the card's picture fading into the card, or for a
 * card without one a warm panel carrying the first sentence of its quote, so every post opens with
 * something to look at. The topic sits on top as a small chip.
 */
export function PostCover({ card, topic, className = "" }: { card: Card; topic: string; className?: string }) {
  const image = card.image;
  const quote = card.quote?.trim();
  const chip = image
    ? "bg-[rgba(20,17,14,0.62)] text-[#f3b65a]"
    : "bg-[var(--cover-chip-bg)] text-[var(--cover-chip-fg)]";
  return (
    <div
      data-post-cover
      className={`relative h-[clamp(110px,25svh,230px)] shrink-0 overflow-hidden ${className}`}
      style={image ? { background: "#14110e" } : { background: "linear-gradient(135deg, var(--cover-from), var(--cover-to))" }}
    >
      {image ? (
        <>
          {/* eslint-disable-next-line @next/next/no-img-element -- media comes from R2, not next/image's optimiser */}
          <img src={mediaUrl(image.url)} alt={image.caption} loading="lazy" decoding="async" className="size-full object-cover" />
          <span aria-hidden="true" className="absolute inset-0 bg-linear-to-b from-transparent from-55% to-surface" />
        </>
      ) : (
        <>
          <span
            aria-hidden="true"
            className="absolute -bottom-[4.5rem] right-3.5 font-serif text-[12.5rem] leading-none text-[var(--cover-mark)]"
          >
            “
          </span>
          {quote ? (
            <p
              aria-hidden="true"
              className="absolute inset-x-5 bottom-4 line-clamp-3 font-serif text-lg font-semibold italic leading-[1.32] text-cover-ink"
            >
              {firstSentence(quote)}
            </p>
          ) : null}
        </>
      )}
      {topic ? (
        <span
          aria-hidden="true"
          className={`absolute left-3.5 top-3.5 rounded-full px-[0.6875rem] py-[0.3125rem] text-[0.6875rem] font-bold uppercase tracking-[0.07em] ${chip}`}
        >
          {topic}
        </span>
      ) : null}
    </div>
  );
}
