import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { CardList } from "@/components/CardPreview";
import { AuthorLinks } from "@/components/CardView";
import { SourceFollowButton } from "@/components/FollowButton";
import { JsonLd } from "@/components/JsonLd";
import { Unavailable } from "@/components/Unavailable";
import { formatAuthors, formatYear, licenceName } from "@/lib/content";
import { siteUrl } from "@/lib/config";
import { getSitemap, getSource, loadOr } from "@/lib/server-api";

export const revalidate = 600;

export async function generateStaticParams() {
  try {
    const sitemap = await getSitemap();
    return sitemap.sources.slice(0, 200).map((s) => ({ id: s.id }));
  } catch {
    return [];
  }
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const { data } = await loadOr(() => getSource(id), null);
  if (!data) return { title: "Source not found", robots: { index: false } };
  const { source, cards } = data;
  const title = `${source.title} by ${formatAuthors(source.authors)}`;
  const description = `${cards.length} one-minute ${cards.length === 1 ? "idea" : "ideas"} from ${source.title} by ${formatAuthors(source.authors)}. ${source.attribution}.`;
  const url = `/sources/${source.id}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { siteName: "Reborn", type: "website", title, description, url },
    twitter: { card: "summary", title, description },
  };
}

export default async function SourcePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data, ok } = await loadOr(() => getSource(id), null);
  if (!ok) return <Unavailable what="this source" />;
  if (!data) notFound();
  const { source, cards, follow } = data;
  const isBook = source.kind === "book" || source.kind === "textbook";

  return (
    <div>
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": isBook ? "Book" : "CreativeWork",
          "@id": `${siteUrl()}/sources/${source.id}`,
          name: source.title,
          url: source.url,
          author: source.authors.map((name) => ({ "@type": "Person", name })),
          translator: source.translator ? { "@type": "Person", name: source.translator } : undefined,
          publisher: source.publisher ? { "@type": "Organization", name: source.publisher } : undefined,
          license: source.licence_url,
          inLanguage: source.language ?? "en",
        }}
      />
      <header className="mx-auto max-w-read">
        <p className="eyebrow capitalize">{source.kind}</p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight text-balance">{source.title}</h1>
        <p className="mt-2 text-lg text-muted">
          by <AuthorLinks authors={source.authors} />
        </p>
        <div className="mt-4">
          <SourceFollowButton id={source.id} title={source.title} initial={follow} />
        </div>

        <dl className="panel mt-6 grid gap-x-6 gap-y-3 p-5 text-[0.9375rem] sm:grid-cols-[auto_1fr]">
          {source.translator ? (
            <>
              <dt className="font-semibold">Translator</dt>
              <dd>{source.translator}</dd>
            </>
          ) : null}
          {source.publisher || source.year != null ? (
            <>
              <dt className="font-semibold">Published</dt>
              <dd>{[source.publisher, source.year != null ? formatYear(source.year) : null].filter(Boolean).join(", ")}</dd>
            </>
          ) : null}
          <dt className="font-semibold">Licence</dt>
          <dd>
            <a href={source.licence_url} className="link" target="_blank" rel="license noopener noreferrer">
              {licenceName(source.licence)}
            </a>
          </dd>
          <dt className="font-semibold">Original</dt>
          <dd className="min-w-0 break-words">
            <a href={source.url} className="link" target="_blank" rel="noopener noreferrer">
              {source.url.replace(/^https?:\/\//, "")}
            </a>
          </dd>
          <dt className="font-semibold">Credit</dt>
          <dd>{source.attribution}</dd>
        </dl>
        {source.licence === "original-summary" ? (
          <p className="mt-3 text-sm text-muted">
            These cards are our own summaries in our own words. Read the original for the full work.
          </p>
        ) : null}
      </header>

      <section aria-labelledby="cards-title" className="mt-12">
        <h2 id="cards-title" className="font-serif text-2xl font-semibold">
          {cards.length} {cards.length === 1 ? "idea" : "ideas"} from this {source.kind}
        </h2>
        <div className="mt-4">
          <CardList cards={cards} />
        </div>
      </section>
    </div>
  );
}
