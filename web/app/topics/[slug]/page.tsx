import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CardList } from "@/components/CardPreview";
import { LoadMoreCards } from "@/components/LoadMoreCards";
import { Unavailable } from "@/components/Unavailable";
import { formatAuthors, TOPICS, topicName } from "@/lib/content";
import { getAllSources, getFeed, getTopics, loadOr } from "@/lib/server-api";

export const revalidate = 600;

export function generateStaticParams() {
  return TOPICS.map((t) => ({ slug: t.slug }));
}

async function resolveTopic(slug: string) {
  const { data: topics } = await loadOr(getTopics, TOPICS.map((t) => ({ ...t, card_count: 0 })));
  return topics.find((t) => t.slug === slug) ?? null;
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const topic = await resolveTopic(slug);
  if (!topic) return { title: "Topic not found", robots: { index: false } };
  const title = `${topic.name} ideas`;
  const description = `One-minute ideas about ${topic.name.toLowerCase()} from books and open sources, each credited to its source.`;
  const url = `/topics/${topic.slug}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { siteName: "Reborn", title, description, url },
    twitter: { card: "summary", title, description },
  };
}

export default async function TopicPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const topic = await resolveTopic(slug);
  if (!topic) notFound();

  const { data, ok } = await loadOr(
    async () => {
      const [sources, feed] = await Promise.all([getAllSources(slug), getFeed({ topics: slug, limit: 12 })]);
      return { sources, feed };
    },
    null,
  );

  return (
    <div>
      <header className="mx-auto max-w-read text-center">
        <p className="eyebrow">Topic</p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight">{topicName(slug, [topic])}</h1>
      </header>

      {!ok || !data ? (
        <div className="mt-8">
          <Unavailable what="this topic" />
        </div>
      ) : (
        <>
          {data.sources.length ? (
            <section aria-labelledby="sources-title" className="mt-10">
              <h2 id="sources-title" className="font-serif text-2xl font-semibold">
                Sources
              </h2>
              <ul className="mt-4 flex flex-wrap gap-3">
                {data.sources.map((s) => (
                  <li key={s.id}>
                    <Link href={`/sources/${s.id}`} className="panel block px-4 py-3 hover:border-accent">
                      <span className="block font-semibold">{s.title}</span>
                      <span className="text-sm text-muted">{formatAuthors(s.authors)}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          <section aria-labelledby="ideas-title" className="mt-12">
            <h2 id="ideas-title" className="font-serif text-2xl font-semibold">
              Ideas
            </h2>
            {data.feed.cards.length === 0 ? (
              <p className="mt-4 text-muted">
                No ideas in this topic yet.{" "}
                <Link href="/contribute" className="link">
                  Contribute the first one
                </Link>
                .
              </p>
            ) : (
              <div className="mt-4">
                <CardList cards={data.feed.cards} showTopic={false} />
                <LoadMoreCards topic={slug} initialCursor={data.feed.next_cursor} />
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}
