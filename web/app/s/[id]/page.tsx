import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CardList } from "@/components/CardPreview";
import { JsonLd } from "@/components/JsonLd";
import { ShareMenu } from "@/components/ShareMenu";
import { Unavailable } from "@/components/Unavailable";
import { excerpt } from "@/lib/content";
import { getPublicStash, loadOr } from "@/lib/server-api";
import { DEFAULT_OG_IMAGE, siteUrl } from "@/lib/config";

export const revalidate = 60; // short: an owner can make the stash private again

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const { data } = await loadOr(() => getPublicStash(id), null);
  if (!data) return { title: "Collection not found", robots: { index: false } };
  const { stash, cards } = data;
  const title = `${stash.name} · a collection by ${stash.owner.display_name}`;
  const description =
    stash.description ||
    (cards.length
      ? `${cards.length} ${cards.length === 1 ? "idea" : "ideas"} including “${cards[0].title}”. ${excerpt(cards[0].body, 100)}`
      : `A collection of ideas by ${stash.owner.display_name} on Reborn.`);
  const url = `/s/${stash.id}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { siteName: "Reborn", type: "website", title, description, url, images: [DEFAULT_OG_IMAGE] },
    twitter: { card: "summary_large_image", title, description, images: [DEFAULT_OG_IMAGE] },
  };
}

export default async function PublicStashPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data, ok } = await loadOr(() => getPublicStash(id), null);
  if (!ok) return <Unavailable what="this collection" />;
  if (!data) notFound();
  const { stash, cards } = data;

  const base = siteUrl();

  return (
    <div>
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "ItemList",
          name: stash.name,
          url: `${base}/s/${stash.id}`,
          itemListElement: cards.map((c, i) => ({
            "@type": "ListItem",
            position: i + 1,
            url: `${base}/ideas/${c.id}`,
            name: c.title,
          })),
        }}
      />
      <header className="mx-auto max-w-read text-center">
        <p className="eyebrow">Collection</p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight text-balance">{stash.name}</h1>
        {stash.description ? <p className="mt-2 text-lg text-muted">{stash.description}</p> : null}
        <p className="mt-3 text-sm text-muted">
          By{" "}
          <Link href={`/u/${stash.owner.handle}`} className="link">
            {stash.owner.display_name}
          </Link>{" "}
          · {stash.card_count} {stash.card_count === 1 ? "idea" : "ideas"}
        </p>
        <div className="mt-4 flex justify-center">
          <ShareMenu path={`/s/${stash.id}`} title={stash.name} what="collection" label />
        </div>
      </header>
      <section aria-label="Ideas in this collection" className="mt-10">
        {cards.length ? <CardList cards={cards} /> : <p className="text-center text-muted">This collection is empty.</p>}
      </section>
    </div>
  );
}
