import Link from "next/link";
import type { ReactNode } from "react";
import { licenceName, paragraphs, SUPPORT_TOPICS, topicName } from "@/lib/content";
import { authorHref } from "@/lib/social";
import type { Card } from "@/lib/types";
import { ExplainerVideo } from "./ExplainerVideo";
import { FitBody } from "./FitBody";
import { Icon } from "./Icon";

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
 * The idea card. Always renders the credit line (linked to the source page,
 * the original and its licence) and, when present, the health disclaimer.
 */
export function CardView({ card, headingLevel = "h1", actions, children, titleHref, feed = false }: CardViewProps) {
  const Heading = headingLevel;
  const Sub = headingLevel === "h1" ? "h2" : "h3";
  // The phone feed's preview. Everything it leaves out is only hidden below md, so tablets and
  // desktops still get the full card; the card's own page has it all.
  const preview = feed && titleHref ? titleHref : null;
  const video = !!card.explainer;
  const phoneOnly = preview ? "max-md:hidden" : "";
  return (
    <article
      className={`mx-auto w-full max-w-read ${preview ? "max-md:flex max-md:min-h-0 max-md:flex-1 max-md:flex-col" : ""}`}
      aria-labelledby={`card-${card.id}-title`}
      data-card-preview={preview ? "" : undefined}
    >
      <p className={`eyebrow ${preview ? "max-md:order-first max-md:text-[0.6875rem]" : ""}`}>
        <Link href={`/topics/${card.topic}`} className="hover:text-accent-text hover:underline">
          {topicName(card.topic)}
        </Link>
      </p>
      <Heading
        id={`card-${card.id}-title`}
        className={`mt-2 font-serif font-semibold leading-tight tracking-tight text-balance ${
          preview
            ? `text-2xl max-md:text-[1.375rem] max-md:leading-[1.22] md:text-4xl ${video ? "max-md:line-clamp-2" : "max-md:line-clamp-3"}`
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
      {/* Source and authors in amber, as in the app: "Meditations · Marcus Aurelius". */}
      <p className={`mt-2 text-sm text-muted ${preview ? "max-md:text-[0.8125rem]" : ""}`} data-testid="card-byline">
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
          <span className={preview ? "max-md:line-clamp-2" : undefined}>
            <strong className="font-semibold">{SUPPORT_TOPICS.has(card.topic) ? "Support note: " : "Health note: "}</strong>
            {card.disclaimer}
          </span>
        </p>
      ) : null}

      {card.explainer ? <ExplainerVideo card={card} feed={feed} /> : null}

      {preview && !video ? (
        // As much as fits above "Read more", clipped (never scrolled): whole lines ending in "…"
        // once measured, faded at the cut until then.
        <FitBody
          className="prose-reborn mt-6 max-md:mt-3 max-md:min-h-0 max-md:flex-1 max-md:overflow-clip max-md:text-[1.0625rem] max-md:leading-[1.6] max-md:[mask-image:linear-gradient(to_bottom,#000_calc(100%-3.5rem),transparent)]"
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

      {preview && (!video || card.body.trim()) ? (
        // Always shown in the preview (it never has Apply it or the full credit), only on phones.
        <p className="mt-3 shrink-0 max-md:order-2 md:hidden">
          <Link href={preview} className="btn btn-small btn-primary gap-2 pl-3.5" data-read-more>
            <Icon name="arrowForward" className="size-[1.125rem]" />
            Read more<span className="sr-only">: {card.title}</span>
          </Link>
        </p>
      ) : null}

      {card.quote ? (
        <figure className={`mt-6 border-l-2 border-oxblood pl-4 ${phoneOnly}`}>
          <blockquote className="font-serif text-xl font-semibold italic leading-relaxed">“{card.quote}”</blockquote>
          <figcaption className="mt-1 text-sm text-muted">
            {card.source.authors.join(", ")}, <cite>{card.source.title}</cite>
          </figcaption>
        </figure>
      ) : null}

      <section
        aria-label="Apply it"
        className={`mt-8 rounded-inset bg-surface-2 px-5 py-4 ${phoneOnly}`}
      >
        <Sub className="eyebrow">Apply it</Sub>
        <p className="mt-1 text-lg leading-relaxed">{card.apply_it}</p>
      </section>

      {children}

      <footer className={`mt-8 border-t border-line pt-4 text-sm text-muted ${phoneOnly}`} data-testid="card-credit">
        <p>
          <Link href={`/sources/${card.source.id}`} className="hover:text-fg hover:underline">
            {card.credit}
          </Link>
        </p>
        <p className="mt-1">
          <a href={card.source.url} className="link" target="_blank" rel="noopener noreferrer">
            Original source<span className="sr-only"> (opens in a new tab)</span>
          </a>
          {" · "}
          Licence:{" "}
          <a href={card.source.licence_url} className="link" target="_blank" rel="license noopener noreferrer">
            {licenceName(card.source.licence)}
          </a>
        </p>
      </footer>
    </article>
  );
}
