import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CardList } from "@/components/CardPreview";
import { CardView } from "@/components/CardView";
import { Comments } from "@/components/Comments";
import { GiftThanks } from "@/components/GiftThanks";
import { JsonLd } from "@/components/JsonLd";
import { ListenButton } from "@/components/ListenButton";
import { PostActions } from "@/components/PostActions";
import { Quiz } from "@/components/Quiz";
import { StashButton } from "@/components/StashButton";
import { Unavailable } from "@/components/Unavailable";
import { ViewTracker } from "@/components/ViewTracker";
import { excerpt, speechText, topicName } from "@/lib/content";
import { SITE_NAME, siteUrl } from "@/lib/config";
import { authorHref } from "@/lib/social";
import { getCard, getPost, getSitemap, getSource, loadOr } from "@/lib/server-api";
import type { Card, Post } from "@/lib/types";

export const revalidate = 600;

/** Prebuild the library's cards when the API is reachable; others render on first request. */
export async function generateStaticParams() {
  try {
    const sitemap = await getSitemap();
    return sitemap.cards.slice(0, 200).map((c) => ({ id: c.id }));
  } catch {
    return [];
  }
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const { data: card } = await loadOr(() => getCard(id), null);
  if (!card) return { title: "Idea not found", robots: { index: false } };
  const description = excerpt(card.body);
  const url = `/ideas/${card.id}`;
  const oembed = `/oembed?url=${encodeURIComponent(`${siteUrl()}${url}`)}&format=json`;
  // og:image and twitter:image come from opengraph-image.tsx / twitter-image.tsx next to this page.
  return {
    title: card.title,
    description,
    alternates: {
      canonical: url,
      types: { "application/json+oembed": [{ url: oembed, title: card.title }] },
    },
    authors: card.source.authors.map((name) => ({ name })),
    openGraph: {
      siteName: "Reborn",
      type: "article",
      title: card.title,
      description,
      url,
      section: topicName(card.topic),
      tags: card.tags ?? undefined,
      authors: card.source.authors.map((name) => `${siteUrl()}${authorHref(name)}`),
    },
    twitter: { card: "summary_large_image", title: card.title, description },
  };
}

function cardJsonLd(card: Card) {
  const url = `${siteUrl()}/ideas/${card.id}`;
  const isBook = card.source.kind === "book" || card.source.kind === "textbook";
  return {
    "@context": "https://schema.org",
    "@type": "Article",
    "@id": url,
    url,
    mainEntityOfPage: url,
    headline: card.title,
    description: excerpt(card.body),
    articleBody: card.body,
    articleSection: topicName(card.topic),
    keywords: card.tags?.length ? card.tags.join(", ") : undefined,
    inLanguage: "en",
    creditText: card.credit,
    publisher: { "@type": "Organization", name: SITE_NAME, url: siteUrl() },
    isBasedOn: {
      "@type": isBook ? "Book" : "CreativeWork",
      "@id": `${siteUrl()}/sources/${card.source.id}`,
      name: card.source.title,
      url: card.source.url,
      author: card.source.authors.map((name) => ({ "@type": "Person", name })),
      license: card.source.licence_url,
    },
  };
}

export default async function IdeaPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data: card, ok } = await loadOr(() => getCard(id), null);
  if (!ok) return <Unavailable what="this idea" />;
  if (!card) notFound();

  const [{ data: source }, { data: loadedPost }] = await Promise.all([
    loadOr(() => getSource(card.source.id), null),
    loadOr(() => getPost(card.id), null),
  ]);
  const related = (source?.cards ?? []).filter((c) => c.id !== card.id);
  const post: Post = loadedPost ?? {
    id: card.id,
    published_at: "",
    card,
    stats: { reactions: {}, comments: 0, favorites: 0, shares: 0, gifts: 0 },
  };

  return (
    <>
      <JsonLd data={cardJsonLd(card)} />
      <ViewTracker cardId={card.id} />
      <Suspense fallback={null}>
        <GiftThanks />
      </Suspense>
      <CardView
        card={card}
        actions={
          <>
            <ListenButton text={speechText(card)} />
            <StashButton cardId={card.id} cardTitle={card.title} />
          </>
        }
      >
        {card.quiz ? <Quiz quiz={card.quiz} /> : null}
      </CardView>
      <PostActions post={post} refresh commentsHref="#comments" />
      <Comments postId={card.id} />

      {related.length ? (
        <section aria-labelledby="related-title" className="mt-16">
          <h2 id="related-title" className="font-serif text-2xl font-semibold">
            More from {card.source.title}
          </h2>
          <div className="mt-4">
            <CardList cards={related.slice(0, 6)} showTopic={false} />
          </div>
        </section>
      ) : null}
    </>
  );
}
