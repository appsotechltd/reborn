import type { Metadata } from "next";
import Link from "next/link";
import { CircleList } from "@/components/CircleList";
import { Icon } from "@/components/Icon";
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
    <div className="space-y-14 max-md:space-y-10">
      <header className="mx-auto max-w-read text-center">
        <h1 className="font-serif text-4xl font-semibold tracking-tight max-md:text-3xl">Discover</h1>
        <p className="mt-3 text-lg text-muted max-md:text-base">What readers are loving this week, and where to start next.</p>
        {/* Phones have no Search link in the header, so Discover leads with it, as in the app. */}
        <Link
          href="/search"
          className="mt-5 flex min-h-12 items-center gap-3 rounded-full border border-line bg-surface-2 px-4 text-left text-muted hover:text-fg md:hidden"
        >
          <Icon name="search" className="size-6" />
          Search ideas
        </Link>
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

          <div className="space-y-8">
            <Link
              href="/sources"
              className="panel flex items-center gap-4 p-5 transition-colors hover:border-accent"
            >
              <span className="grid size-11 shrink-0 place-items-center rounded-full bg-accent-soft text-accent-text">
                <Icon name="book" className="size-6" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block font-serif text-xl font-semibold">Browse all books and authors</span>
                <span className="block text-sm text-muted">The whole library, with every idea and video from each.</span>
              </span>
              <Icon name="chevronRight" className="size-6 text-muted" />
            </Link>

            <div className="grid grid-cols-1 gap-10 md:grid-cols-2">
              <section aria-labelledby="books-title">
                <div className="flex items-baseline justify-between gap-4">
                  <h2 id="books-title" className="font-serif text-2xl font-semibold">
                    Popular books
                  </h2>
                  <Link href="/sources" className="link text-sm">
                    All books
                  </Link>
                </div>
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
                <div className="flex items-baseline justify-between gap-4">
                  <h2 id="authors-title" className="font-serif text-2xl font-semibold">
                    Popular authors
                  </h2>
                  <Link href="/authors" className="link text-sm">
                    All authors
                  </Link>
                </div>
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
