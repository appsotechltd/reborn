import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CardsBrowser } from "@/components/CardsBrowser";
import { AuthorFollowButton } from "@/components/FollowButton";
import { JsonLd } from "@/components/JsonLd";
import { VideoCount } from "@/components/Library";
import { Unavailable } from "@/components/Unavailable";
import { licenceName, topicName } from "@/lib/content";
import { siteUrl } from "@/lib/config";
import { getAuthor, loadOr } from "@/lib/server-api";
import { authorHref } from "@/lib/social";

export const revalidate = 600;

/** Route params may arrive percent-encoded; decode once, tolerating stray "%". */
function authorName(raw: string): string {
  if (!raw.includes("%")) return raw;
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

export async function generateMetadata({ params }: { params: Promise<{ name: string }> }): Promise<Metadata> {
  const name = authorName((await params).name);
  const { data } = await loadOr(() => getAuthor(name), null);
  if (!data) return { title: "Author not found", robots: { index: false } };
  const n = data.sources.length;
  const cards = data.card_count ?? data.sources.reduce((c, s) => c + s.card_count, 0);
  const title = data.name;
  const description = `${cards} one-minute ${cards === 1 ? "idea" : "ideas"} from ${n} ${n === 1 ? "work" : "works"} by ${data.name} on Reborn, each credited to its source.`;
  const url = authorHref(data.name);
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { siteName: "Reborn", type: "profile", title, description, url },
    twitter: { card: "summary", title, description },
  };
}

export default async function AuthorPage({ params }: { params: Promise<{ name: string }> }) {
  const name = authorName((await params).name);
  const { data, ok } = await loadOr(() => getAuthor(name), null);
  if (!ok) return <Unavailable what="this author" />;
  if (!data) notFound();
  const cards = data.card_count ?? data.sources.reduce((n, s) => n + s.card_count, 0);
  const videos = data.video_count ?? 0;

  return (
    <div className="mx-auto max-w-3xl">
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "Person",
          "@id": `${siteUrl()}${authorHref(data.name)}`,
          name: data.name,
        }}
      />
      <header className="mx-auto max-w-read text-center">
        <p className="eyebrow">Author</p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight text-balance">{data.name}</h1>
        <p className="mt-2 text-muted">
          {cards} {cards === 1 ? "idea" : "ideas"}
          {videos ? `, ${videos} ${videos === 1 ? "video" : "videos"},` : ""} from {data.sources.length}{" "}
          {data.sources.length === 1 ? "work" : "works"}
        </p>
        <div className="mt-4 flex justify-center">
          <AuthorFollowButton name={data.name} initial={{ followers: data.followers, is_following: false }} />
        </div>
        <p className="mt-2 text-sm text-muted">Follow to see new ideas from {data.name} in your timeline.</p>
      </header>

      <section aria-labelledby="works-title" className="mt-10">
        <h2 id="works-title" className="font-serif text-2xl font-semibold">
          Works
        </h2>
        <ul className="mt-4 divide-y divide-line border-y border-line">
          {data.sources.map((s) => (
            <li key={s.id} className="py-5">
              <h3 className="font-serif text-xl font-semibold">
                <Link href={`/sources/${s.id}`} className="inline-flex items-center hover:underline pointer-coarse:min-h-11">
                  {s.title}
                </Link>
              </h3>
              <p className="mt-1 text-muted">
                <span className="capitalize">{s.kind}</span> · {licenceName(s.licence)} · {s.card_count}{" "}
                {s.card_count === 1 ? "idea" : "ideas"}
              </p>
              <p className="mt-2 flex flex-wrap items-center gap-2 text-sm">
                <VideoCount count={s.video_count} />
                {s.topics.map((t) => (
                  <Link key={t} href={`/topics/${t}`} className="chip hover:text-fg pointer-coarse:min-h-11">
                    {topicName(t)}
                  </Link>
                ))}
              </p>
            </li>
          ))}
        </ul>
      </section>

      {data.cards?.length ? (
        <div className="mt-12">
          <CardsBrowser
            cards={data.cards}
            queue={`author:${data.name}`}
            listenLabel="Listen to this author"
            context={`by ${data.name}`}
          />
        </div>
      ) : null}
    </div>
  );
}
