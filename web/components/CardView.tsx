import Link from "next/link";
import type { ReactNode } from "react";
import { licenceName, paragraphs, topicName } from "@/lib/content";
import type { Card } from "@/lib/types";

interface CardViewProps {
  card: Card;
  /** Use "h1" on the card's own page, "h2" when embedded in another page. */
  headingLevel?: "h1" | "h2";
  /** Extra controls (Listen, Stash...) rendered under the title. */
  actions?: ReactNode;
  /** Content rendered after Apply it and before the credit (e.g. the quiz). */
  children?: ReactNode;
}

/**
 * The idea card. Always renders the credit line (linked to the source page,
 * the original and its licence) and, when present, the health disclaimer.
 */
export function CardView({ card, headingLevel = "h1", actions, children }: CardViewProps) {
  const Heading = headingLevel;
  const Sub = headingLevel === "h1" ? "h2" : "h3";
  return (
    <article className="mx-auto w-full max-w-read" aria-labelledby={`card-${card.id}-title`}>
      <p className="eyebrow">
        <Link href={`/topics/${card.topic}`} className="hover:text-accent hover:underline">
          {topicName(card.topic)}
        </Link>
      </p>
      <Heading
        id={`card-${card.id}-title`}
        className="mt-2 font-serif text-3xl font-semibold leading-tight tracking-tight text-balance sm:text-4xl"
      >
        {card.title}
      </Heading>
      <p className="mt-2 text-sm text-muted">
        From{" "}
        <Link href={`/sources/${card.source.id}`} className="link">
          {card.source.title}
        </Link>
        {card.locator ? <span> · {card.locator}</span> : null}
      </p>

      {actions ? <div className="mt-4 flex flex-wrap gap-2">{actions}</div> : null}

      {card.disclaimer ? (
        <p
          role="note"
          aria-label="Health disclaimer"
          className="mt-6 rounded-lg border border-warn-border bg-warn px-4 py-3 text-sm text-warn-fg"
        >
          <strong className="font-semibold">Health note: </strong>
          {card.disclaimer}
        </p>
      ) : null}

      <div className="prose-reborn mt-6">
        {paragraphs(card.body).map((p, i) => (
          <p key={i}>{p}</p>
        ))}
      </div>

      {card.quote ? (
        <figure className="mt-6 border-l-4 border-accent pl-4">
          <blockquote className="font-serif text-lg italic leading-relaxed">“{card.quote}”</blockquote>
          <figcaption className="mt-1 text-sm text-muted">
            {card.source.authors.join(", ")}, <cite>{card.source.title}</cite>
          </figcaption>
        </figure>
      ) : null}

      <section
        aria-label="Apply it"
        className="mt-8 rounded-xl border-l-4 border-apply-border bg-apply px-5 py-4 text-apply-fg"
      >
        <Sub className="text-sm font-bold uppercase tracking-wider">Apply it</Sub>
        <p className="mt-1 font-serif text-lg leading-relaxed">{card.apply_it}</p>
      </section>

      {children}

      <footer className="mt-8 border-t border-line pt-4 text-sm text-muted" data-testid="card-credit">
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
