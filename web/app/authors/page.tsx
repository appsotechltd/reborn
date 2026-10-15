import type { Metadata } from "next";
import { LibraryBrowser, LibraryHeader } from "@/components/Library";
import { Unavailable } from "@/components/Unavailable";
import { topicName } from "@/lib/content";
import { libraryFilters, type SearchParams } from "@/lib/library";
import { getAuthorsPage, loadOr } from "@/lib/server-api";
import { DEFAULT_OG_IMAGE } from "@/lib/config";

export const revalidate = 600;

const description =
  "Every author in the Reborn library: pick one to see all of their books, idea cards and videos.";

export async function generateMetadata({ searchParams }: { searchParams: SearchParams }): Promise<Metadata> {
  const { q, topic } = await libraryFilters(searchParams);
  const title = topic ? `${topicName(topic)} authors` : "All authors";
  return {
    title,
    description,
    alternates: { canonical: topic && !q ? `/authors?topic=${topic}` : "/authors" },
    // Searches are endless near-duplicates; the topic filters are worth indexing.
    robots: q ? { index: false, follow: true } : undefined,
    openGraph: { siteName: "Reborn", title, description, url: "/authors", images: [DEFAULT_OG_IMAGE] },
    twitter: { card: "summary_large_image", title, description, images: [DEFAULT_OG_IMAGE] },
  };
}

export default async function AuthorsPage({ searchParams }: { searchParams: SearchParams }) {
  const { q, topic } = await libraryFilters(searchParams);
  const { data, ok } = await loadOr(() => getAuthorsPage({ q: q || undefined, topic: topic || undefined }), null);
  return (
    <div className="mx-auto max-w-3xl">
      <LibraryHeader current="authors" />
      {!ok || !data ? (
        <div className="mt-8">
          <Unavailable what="the authors" />
        </div>
      ) : (
        <LibraryBrowser
          key={`${q}|${topic}`}
          kind="authors"
          initial={{ items: data.authors, cursor: data.next_cursor }}
          initialQuery={q}
          initialTopic={topic}
        />
      )}
    </div>
  );
}
