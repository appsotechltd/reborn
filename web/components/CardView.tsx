import Link from "next/link";
import type { ReactNode } from "react";
import { evidenceLabel, paragraphs, SUPPORT_TOPICS, topicName } from "@/lib/content";
import { authorHref } from "@/lib/social";
import type { Card } from "@/lib/types";
import { CardPicture } from "./CardPicture";
import { ExplainerVideo } from "./ExplainerVideo";
import { FitBody } from "./FitBody";
import { Icon } from "./Icon";
import { IllustratedVideo } from "./IllustratedVideo";
import { ListenPill } from "./ListenButton";

interface CardViewProps {
  card: Card;
  /** Use "h1" on the card's own page, "h2" when embedded in another page. */
  headingLevel?: "h1" | "h2";
  /** Extra controls (Listen, Stash...) rendered under the title. */
  actions?: ReactNode;
  /** Content rendered after Apply it and before the credit (e.g. the quiz). */
  children?: ReactNode;
  /** Link the title (used when the card is shown in a list such as the timeline). */
  titleHref?: string;
  /**
   * In the home feed: the explainer plays by itself (muted) while it is on screen, and below md
   * (the full-screen phone feed, with `titleHref`) the card becomes a preview that fits its slide:
   * topic, title, source and as much of the body as fits (whole lines, ending in "…"), then "Read more".
   */
  feed?: boolean;
}

/** Author names, each linked to its author page. */
export function AuthorLinks({ authors, className = "link" }: { authors: string[]; className?: string }) {
  return (
    <>
      {authors.map((name, i) => (
        <span key={name}>
          {i > 0 ? (i === authors.length - 1 ? " and " : ", ") : null}
          <Link href={authorHref(name)} className={className}>
            {name}
          </Link>
        </span>
      ))}
    </>
  );
}

/**
 * The idea card, with the health disclaimer when present. The full credit, original
 * link and licence live on the source page, linked from the byline under the title.
 */
export function CardView({ card, headingLevel = "h1", actions, children, titleHref, feed = false }: CardViewProps) {
  const Heading = headingLevel;
  const Sub = headingLevel === "h1" ? "h2" : "h3";
  // The phone feed's preview. Everything it leaves out is only hidden below md, so tablets and
  // desktops still get the full card; the card's own page has it all.
  const preview = feed && titleHref ? titleHref : null;
  const video = !!card.explainer || !!card.video?.scenes?.length;
  const phoneOnly = preview ? "max-md:hidden" : "";
  return (
    <article
      className={`mx-auto w-full max-w-read ${preview ? "max-md:flex max-md:min-h-0 max-md:flex-1 max-md:flex-col" : ""}`}
      aria-labelledby={`card-${card.id}-title`}
      data-card-preview={preview ? "" : undefined}
    >
      {/* The picture tops the full card; the phone feed's preview stays text, and a video card has its video. */}
      {card.image && !video ? <CardPicture image={card.image} className={phoneOnly} /> : null}
      {/* In the phone feed the topic rides on the post's cover instead (a video post has no cover). */}
      <p className={`eyebrow ${preview ? (video ? "max-md:order-first max-md:text-[0.6875rem]" : "max-md:hidden") : ""}`}>
        <Link href={`/topics/${card.topic}`} className="hover:text-accent-text hover:underline">
          {topicName(card.topic)}
        </Link>
        {evidenceLabel(card.tags) ? <span className="text-muted"> · {evidenceLabel(card.tags)}</span> : null}
      </p>
      <Heading
        id={`card-${card.id}-title`}
        className={`mt-2 font-serif font-semibold leading-tight tracking-tight text-balance ${
          preview
            ? `text-2xl max-md:mt-1 max-md:shrink-0 max-md:text-[1.5625rem] max-md:leading-[1.16] md:text-[1.625rem] lg:text-4xl ${video ? "max-md:line-clamp-2" : "max-md:line-clamp-3"}`
            : "text-3xl sm:text-4xl"
        }`}
      >
        {titleHref ? (
          <Link href={titleHref} className="hover:underline">
            {card.title}
          </Link>
        ) : (
          card.title
        )}
      </Heading>
      {/* Source and authors in amber, as in the app: "Meditations · Marcus Aurelius". A member's own card reads "by <name>", linked to their page. */}
      <p className={`mt-2 text-sm text-muted ${preview ? "max-md:shrink-0 max-md:text-[0.8125rem]" : ""}`} data-testid="card-byline">
        {card.author ? (
          <>
            by{" "}
            <Link href={`/u/${card.author.handle}`} className="font-semibold text-accent-text hover:underline">
              {card.author.display_name}
            </Link>
          </>
        ) : (
          <>
            <span className="sr-only">From </span>
            <Link href={`/sources/${card.source.id}`} className="font-semibold text-accent-text hover:underline">
              {card.source.title}
            </Link>
            {card.source.authors.map((name, i) => (
              <span key={name}>
                <span aria-hidden="true"> · </span>
                {i === 0 ? <span className="sr-only"> by </span> : <span className="sr-only">, </span>}
                <Link href={authorHref(name)} className="font-semibold text-accent-text hover:underline">
                  {name}
                </Link>
              </span>
            ))}
            {card.locator ? <span className={preview ? "max-md:hidden" : undefined}> · {card.locator}</span> : null}
          </>
        )}
      </p>

      {actions ? <div className="mt-4 flex flex-wrap gap-2">{actions}</div> : null}

      {card.disclaimer ? (
        <p
          role="note"
          aria-label={SUPPORT_TOPICS.has(card.topic) ? "Support note" : "Health disclaimer"}
          className={`mt-6 rounded-inset border border-warn-border bg-warn px-4 py-3 text-sm text-warn-fg ${
            preview ? "max-md:order-1 max-md:mt-3 max-md:py-2 max-md:text-xs" : ""
          }`}
        >
          {/* Clamp an inner span: clamping the padded box lets a third line show in its padding. */}
          <span className={preview ? "max-md:line-clamp-2" : undefined} data-fit-shrink={preview ? "" : undefined}>
            <strong className="font-semibold">{SUPPORT_TOPICS.has(card.topic) ? "Support note: " : "Health note: "}</strong>
            {card.disclaimer}
          </span>
        </p>
      ) : null}

      {card.explainer ? <ExplainerVideo card={card} feed={feed} /> : null}
      {!card.explainer && card.video?.scenes?.length ? <IllustratedVideo video={card.video} title={card.title} feed={feed} /> : null}

      {preview && !video ? (
        // As much as fits above "Read more", clipped (never scrolled): whole lines ending in "…"
        // once measured, faded at the cut until then.
        <FitBody
          className="prose-reborn mt-6 max-md:mt-3 max-md:min-h-0 max-md:flex-1 max-md:overflow-clip max-md:text-base max-md:leading-[1.55] max-md:[mask-image:linear-gradient(to_bottom,#000_calc(100%-3.5rem),transparent)]"
        >
          {paragraphs(card.body).map((p, i) => (
            <p key={i}>{p}</p>
          ))}
        </FitBody>
      ) : (
        <div data-card-body className={`prose-reborn mt-6 ${preview && video ? "max-md:hidden" : ""}`}>
          {paragraphs(card.body).map((p, i) => (
            <p key={i}>{p}</p>
          ))}
        </div>
      )}

      {preview ? (
        // Always shown in the preview (it never has Apply it or the full credit), only on phones:
        // "Read the idea" for the card's page and Listen, as in the app.
        <div className="mt-3 flex shrink-0 items-center gap-2 max-md:order-2 md:hidden">
          {!video || card.body.trim() ? (
            <Link href={preview} className="btn btn-primary h-[2.875rem] flex-1 gap-2" data-read-more>
              Read the idea<span className="sr-only">: {card.title}</span>
              <Icon name="arrowForward" className="size-[1.125rem]" />
            </Link>
          ) : null}
          <ListenPill card={card} />
        </div>
      ) : null}

      {card.quote ? (
        // The quote on a soft panel with a large amber mark, as in the app.
        <figure className={`relative mt-6 overflow-hidden rounded-[1.25rem] bg-quote-panel px-5 pb-4 pt-9 ${phoneOnly}`}>
          <span aria-hidden="true" className="absolute left-4 top-0 font-serif text-[4.5rem] leading-none text-accent">
            “
          </span>
          <blockquote className="font-serif text-lg font-semibold italic leading-relaxed">{card.quote}</blockquote>
          <figcaption className="mt-2 text-sm text-muted">
            {card.source.authors.join(", ")}, <cite>{card.source.title}</cite>
            {card.locator ? <> · {card.locator}</> : null}
          </figcaption>
        </figure>
      ) : null}

      {/* Optional on members' own cards. */}
      {card.apply_it?.trim() ? (
        <section
          aria-label="Apply it"
          className={`mt-6 rounded-[1.25rem] bg-amber-wash px-5 py-4 text-on-amber-wash ${phoneOnly}`}
        >
          <Sub className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-[0.12em] text-accent-text">
            <Icon name="fire" className="size-4 text-accent" />
            Apply it
          </Sub>
          <p className="mt-1.5 text-lg leading-relaxed">{card.apply_it}</p>
        </section>
      ) : null}

      {children}

    </article>
  );
}
