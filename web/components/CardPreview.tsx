import Link from "next/link";
import { excerpt, topicName } from "@/lib/content";
import type { Card } from "@/lib/types";

/** Compact card for lists. Shows the credit line in short form. */
export function CardPreview({ card, showTopic = true }: { card: Card; showTopic?: boolean }) {
  return (
    <li className="panel relative p-5 transition-colors hover:border-accent focus-within:border-accent">
      {showTopic ? <p className="eyebrow">{topicName(card.topic)}</p> : null}
      <h3 className="mt-1 font-serif text-xl font-semibold leading-snug">
        <Link href={`/ideas/${card.id}`} className="after:absolute after:inset-0 hover:underline focus-visible:outline-none">
          {card.title}
        </Link>
      </h3>
      <p className="mt-2 text-[0.9375rem] leading-relaxed text-muted">{excerpt(card.body, 150)}</p>
      <p className="mt-3 text-xs text-muted">{card.credit}</p>
    </li>
  );
}

export function CardList({ cards, showTopic }: { cards: Card[]; showTopic?: boolean }) {
  return (
    <ul className="grid gap-4 sm:grid-cols-2">
      {cards.map((c) => (
        <CardPreview key={c.id} card={c} showTopic={showTopic} />
      ))}
    </ul>
  );
}
