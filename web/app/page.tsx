import type { Metadata } from "next";
import Link from "next/link";
import { CardList } from "@/components/CardPreview";
import { JsonLd } from "@/components/JsonLd";
import { Unavailable } from "@/components/Unavailable";
import { excerpt, TOPICS } from "@/lib/content";
import { SITE_NAME, SITE_TAGLINE, siteUrl } from "@/lib/config";
import { getDaily, getFeed, getTopics, loadOr } from "@/lib/server-api";
import type { Card, Topic } from "@/lib/types";

export const revalidate = 600;

export const metadata: Metadata = {
  title: { absolute: `${SITE_NAME}: ${SITE_TAGLINE}` },
  alternates: { canonical: "/" },
  openGraph: {
    siteName: "Reborn",
    title: SITE_NAME,
    description: SITE_TAGLINE,
    url: "/",
  },
  twitter: { card: "summary", title: SITE_NAME, description: SITE_TAGLINE },
};

export default async function HomePage() {
  const { data, ok } = await loadOr(
    async () => {
      const [daily, topics, feed] = await Promise.all([getDaily(), getTopics(), getFeed({ limit: 6 })]);
      return { daily, topics, feed };
    },
    null as null | { daily: { date: string; card: Card }; topics: Topic[]; feed: { cards: Card[] } },
  );

  const topics: Topic[] = data?.topics ?? TOPICS.map((t) => ({ ...t, card_count: 0 }));
  const daily = data?.daily;
  const latest = (data?.feed.cards ?? []).filter((c) => c.id !== daily?.card.id);

  return (
    <div className="space-y-16">
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "WebSite",
          name: SITE_NAME,
          url: siteUrl(),
          potentialAction: {
            "@type": "SearchAction",
            target: `${siteUrl()}/search?q={search_term_string}`,
            "query-input": "required name=search_term_string",
          },
        }}
      />
      <section aria-labelledby="hero-title" className="mx-auto max-w-read text-center">
        <h1 id="hero-title" className="font-serif text-4xl font-semibold tracking-tight text-balance sm:text-5xl">
          Big ideas, one minute at a time.
        </h1>
        <p className="mt-4 text-lg text-muted text-pretty">
          Reborn turns ideas from great books and open sources into short idea cards you can read, apply and
          remember. Every card credits where it came from.
        </p>
      </section>

      {!ok ? <Unavailable what="today's idea" /> : null}

      {daily ? (
        <section aria-labelledby="daily-title" className="mx-auto max-w-read">
          <p className="eyebrow">
            Today&apos;s idea · <time dateTime={daily.date}>{daily.date}</time>
          </p>
          <div className="panel mt-3 p-6 sm:p-8">
            <h2 id="daily-title" className="font-serif text-2xl font-semibold leading-snug sm:text-3xl">
              <Link href={`/ideas/${daily.card.id}`} className="hover:underline">
                {daily.card.title}
              </Link>
            </h2>
            <p className="prose-reborn mt-3 text-muted">{excerpt(daily.card.body, 220)}</p>
            <p className="mt-4 text-sm text-muted">{daily.card.credit}</p>
            <Link href={`/ideas/${daily.card.id}`} className="btn btn-primary mt-5">
              Read the idea <span aria-hidden="true">→</span>
            </Link>
          </div>
        </section>
      ) : null}

      <section aria-labelledby="topics-title">
        <h2 id="topics-title" className="font-serif text-2xl font-semibold">
          Explore by topic
        </h2>
        <ul className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
          {topics.map((t) => (
            <li key={t.slug}>
              <Link
                href={`/topics/${t.slug}`}
                className="panel flex h-full flex-col justify-between p-4 transition-colors hover:border-accent"
              >
                <span className="font-semibold">{t.name}</span>
                {ok ? (
                  <span className="mt-1 text-sm text-muted">
                    {t.card_count === 0 ? "Coming soon" : `${t.card_count} ${t.card_count === 1 ? "idea" : "ideas"}`}
                  </span>
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      </section>

      {latest.length ? (
        <section aria-labelledby="latest-title">
          <div className="flex items-baseline justify-between gap-4">
            <h2 id="latest-title" className="font-serif text-2xl font-semibold">
              More ideas
            </h2>
            <Link href="/sources" className="link text-sm">
              Browse all sources
            </Link>
          </div>
          <div className="mt-4">
            <CardList cards={latest} />
          </div>
        </section>
      ) : null}
    </div>
  );
}
