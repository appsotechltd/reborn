import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { excerpt, licenceName, paragraphs, topicName } from "@/lib/content";
import { SITE_NAME } from "@/lib/config";
import { getCard, loadOr } from "@/lib/server-api";

export const revalidate = 600;

// Framable from any site: see the /embed headers in next.config.ts.

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const { data: card } = await loadOr(() => getCard(id), null);
  if (!card) return { title: "Idea not found", robots: { index: false } };
  return {
    title: card.title,
    description: excerpt(card.body),
    alternates: { canonical: `/ideas/${card.id}` },
    robots: { index: false, follow: true },
  };
}

export default async function EmbedIdeaPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data: card, ok } = await loadOr(() => getCard(id), null);
  if (!ok) {
    return <p className="p-6 text-center text-muted">This idea couldn&apos;t be loaded just now.</p>;
  }
  if (!card) notFound();
  const href = `/ideas/${card.id}`;

  return (
    <article className="mx-auto max-w-[560px] bg-surface p-5 sm:p-6" aria-labelledby="embed-title">
      <p className="eyebrow flex items-center justify-between gap-3">
        <span>{topicName(card.topic)}</span>
        <Link href="/" target="_blank" rel="noopener" className="font-serif text-base font-semibold normal-case tracking-tight text-fg">
          {SITE_NAME}
          <span className="text-accent-text">.</span>
        </Link>
      </p>
      <h1 id="embed-title" className="mt-2 font-serif text-2xl font-semibold leading-snug">
        <Link href={href} target="_blank" rel="noopener" className="hover:underline">
          {card.title}
        </Link>
      </h1>
      {card.disclaimer ? (
        <p role="note" aria-label="Health disclaimer" className="mt-3 rounded-inset border border-warn-border bg-warn px-3 py-2 text-sm text-warn-fg">
          <strong className="font-semibold">Health note: </strong>
          {card.disclaimer}
        </p>
      ) : null}
      <div className="prose-reborn mt-3 text-[1.0625rem]">
        {paragraphs(card.body).map((p, i) => (
          <p key={i}>{p}</p>
        ))}
      </div>
      {card.apply_it?.trim() ? (
        <div className="mt-4 rounded-inset bg-surface-2 px-4 py-3">
          <p className="eyebrow">Apply it</p>
          <p className="mt-1">{card.apply_it}</p>
        </div>
      ) : null}
      <footer className="mt-4 border-t border-line pt-3 text-xs text-muted" data-testid="card-credit">
        <p>{card.credit}</p>
        <p className="mt-1">
          {/* A member's card has no book behind it: its credit names the member. */}
          {card.author ? null : (
            <>
              <a href={card.source.url} className="link" target="_blank" rel="noopener noreferrer">
                Original source
              </a>
              {" · "}Licence:{" "}
              <a href={card.source.licence_url} className="link" target="_blank" rel="license noopener noreferrer">
                {licenceName(card.source.licence)}
              </a>
              {" · "}
            </>
          )}
          <Link href={href} className="link" target="_blank" rel="noopener">
            Read on {SITE_NAME}
          </Link>
        </p>
      </footer>
    </article>
  );
}
