import type { Metadata } from "next";
import Link from "next/link";
import { CircleList } from "@/components/CircleList";
import { PostPreviewList } from "@/components/PostPreview";
import { TrendingPosts } from "@/components/TrendingPosts";
import { Unavailable } from "@/components/Unavailable";
import { formatAuthors } from "@/lib/content";
import { getDiscover, loadOr } from "@/lib/server-api";
import { authorHref } from "@/lib/social";

export const revalidate = 600;

const description = "Trending ideas, new posts, popular books and authors, and book circles on Reborn.";

export const metadata: Metadata = {
  title: "Discover",
  description,
  alternates: { canonical: "/discover" },
  openGraph: { siteName: "Reborn", title: "Discover", description, url: "/discover" },
  twitter: { card: "summary", title: "Discover", description },
};

export default async function DiscoverPage() {
  const { data, ok } = await loadOr(getDiscover, null);
  return (
    <div className="space-y-14">
      <header className="mx-auto max-w-read text-center">
        <h1 className="font-serif text-4xl font-semibold tracking-tight">Discover</h1>
        <p className="mt-3 text-lg text-muted">What readers are loving this week, and where to start next.</p>
      </header>
      {!ok || !data ? (
        <Unavailable what="Discover" />
      ) : (
        <>
          <section aria-labelledby="trending-title">
            <h2 id="trending-title" className="font-serif text-2xl font-semibold">
              Trending this week
            </h2>
            <div className="mt-4">
              <TrendingPosts initial={data.trending} />
            </div>
          </section>

          {data.new.length ? (
            <section aria-labelledby="new-title">
              <h2 id="new-title" className="font-serif text-2xl font-semibold">
                New on Reborn
              </h2>
              <div className="mt-4">
                <PostPreviewList posts={data.new.slice(0, 6)} />
              </div>
            </section>
          ) : null}

          <div className="grid grid-cols-1 gap-10 md:grid-cols-2">
            <section aria-labelledby="books-title">
              <h2 id="books-title" className="font-serif text-2xl font-semibold">
                Popular books
              </h2>
              <ol className="mt-4 divide-y divide-line border-y border-line">
                {data.books.map((b) => (
                  <li key={b.id} className="relative flex items-baseline justify-between gap-3 py-3">
                    <span className="min-w-0">
                      <Link href={`/sources/${b.id}`} className="font-semibold after:absolute after:inset-0 hover:underline">
                        {b.title}
                      </Link>
                      <span className="block truncate text-sm text-muted">{formatAuthors(b.authors)}</span>
                    </span>
                    <span className="shrink-0 text-sm text-muted">
                      {b.followers} {b.followers === 1 ? "follower" : "followers"}
                    </span>
                  </li>
                ))}
              </ol>
            </section>
            <section aria-labelledby="authors-title">
              <h2 id="authors-title" className="font-serif text-2xl font-semibold">
                Popular authors
              </h2>
              <ol className="mt-4 divide-y divide-line border-y border-line">
                {data.authors.map((a) => (
                  <li key={a.name} className="relative flex items-baseline justify-between gap-3 py-3">
                    <span className="min-w-0">
                      <Link href={authorHref(a.name)} className="font-semibold after:absolute after:inset-0 hover:underline">
                        {a.name}
                      </Link>
                      <span className="block text-sm text-muted">
                        {a.sources} {a.sources === 1 ? "work" : "works"}
                      </span>
                    </span>
                    <span className="shrink-0 text-sm text-muted">
                      {a.followers} {a.followers === 1 ? "follower" : "followers"}
                    </span>
                  </li>
                ))}
              </ol>
            </section>
          </div>

          <section aria-labelledby="circles-title">
            <div className="flex items-baseline justify-between gap-4">
              <h2 id="circles-title" className="font-serif text-2xl font-semibold">
                Book circles
              </h2>
              <Link href="/circles" className="link text-sm">
                All circles
              </Link>
            </div>
            <div className="mt-4">
              {data.circles.length ? (
                <CircleList circles={data.circles} />
              ) : (
                <p className="text-muted">
                  No circles yet. Start one from any{" "}
                  <Link href="/sources" className="link">
                    book&apos;s page
                  </Link>
                  .
                </p>
              )}
            </div>
          </section>
        </>
      )}
    </div>
  );
}
