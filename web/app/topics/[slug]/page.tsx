import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CardList } from "@/components/CardPreview";
import { breadcrumbsJsonLd, JsonLd } from "@/components/JsonLd";
import { LoadMoreCards } from "@/components/LoadMoreCards";
import { ShareMenu } from "@/components/ShareMenu";
import { SubjectList } from "@/components/Subjects";
import { Unavailable } from "@/components/Unavailable";
import { formatAuthors, TOPICS, topicName } from "@/lib/content";
import { siteUrl } from "@/lib/config";
import { getAllSources, getFeed, getSubjects, getTopics, loadOr } from "@/lib/server-api";

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
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function TopicPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const topic = await resolveTopic(slug);
  if (!topic) notFound();

  const { data, ok } = await loadOr(
    async () => {
      const [sources, feed, subjects] = await Promise.all([
        getAllSources(slug),
        getFeed({ topics: slug, limit: 12 }),
        // Subjects are extra: an outage there leaves the rest of the topic up.
        getSubjects(slug).catch(() => []),
      ]);
      return { sources, feed, subjects };
    },
    null,
  );

  const base = siteUrl();
  const url = `${base}/topics/${topic.slug}`;

  return (
    <div>
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "CollectionPage",
          "@id": url,
          url,
          name: `${topic.name} ideas`,
          description: `One-minute ideas about ${topic.name.toLowerCase()} from books and open sources, each credited to its source.`,
          image: `${url}/opengraph-image`,
          inLanguage: "en",
          isPartOf: { "@type": "WebSite", name: "Reborn", url: base },
          mainEntity: data?.feed.cards.length
            ? {
                "@type": "ItemList",
                itemListElement: data.feed.cards.map((c, i) => ({
                  "@type": "ListItem",
                  position: i + 1,
                  url: `${base}/ideas/${c.id}`,
                  name: c.title,
                })),
              }
            : undefined,
        }}
      />
      <JsonLd data={breadcrumbsJsonLd(base, [[topic.name, `/topics/${topic.slug}`]])} />
      <header className="mx-auto max-w-read text-center">
        <p className="eyebrow">Topic</p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight">{topicName(slug, [topic])}</h1>
        <div className="mt-4 flex justify-center">
          <ShareMenu path={`/topics/${topic.slug}`} title={`${topic.name} ideas on Reborn`} what="topic" label />
        </div>
      </header>

      {!ok || !data ? (
        <div className="mt-8">
          <Unavailable what="this topic" />
        </div>
      ) : (
        <>
          {data.subjects.length ? <SubjectList subjects={data.subjects} topic={slug} /> : null}

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
