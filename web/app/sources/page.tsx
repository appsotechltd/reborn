import type { Metadata } from "next";
import { LibraryBrowser, LibraryHeader } from "@/components/Library";
import { Unavailable } from "@/components/Unavailable";
import { topicName } from "@/lib/content";
import { libraryFilters, type SearchParams } from "@/lib/library";
import { getSourcesPage, loadOr } from "@/lib/server-api";

export const revalidate = 600;

const description =
  "Every book, textbook, guide and article in the Reborn library: pick one to see all of its idea cards and videos.";

export async function generateMetadata({ searchParams }: { searchParams: SearchParams }): Promise<Metadata> {
  const { q, topic } = await libraryFilters(searchParams);
  const title = topic ? `${topicName(topic)} books` : "All books";
  return {
    title,
    description,
    alternates: { canonical: topic && !q ? `/sources?topic=${topic}` : "/sources" },
    // Searches are endless near-duplicates; the topic filters are worth indexing.
    robots: q ? { index: false, follow: true } : undefined,
    openGraph: { siteName: "Reborn", title, description, url: "/sources" },
    twitter: { card: "summary", title, description },
  };
}

export default async function SourcesPage({ searchParams }: { searchParams: SearchParams }) {
  const { q, topic } = await libraryFilters(searchParams);
  const { data, ok } = await loadOr(() => getSourcesPage({ q: q || undefined, topic: topic || undefined }), null);
  return (
    <div className="mx-auto max-w-3xl">
      <LibraryHeader current="books" />
      {!ok || !data ? (
        <div className="mt-8">
          <Unavailable what="the library" />
        </div>
      ) : (
        <LibraryBrowser
          key={`${q}|${topic}`}
          kind="books"
          initial={{ items: data.sources, cursor: data.next_cursor }}
          initialQuery={q}
          initialTopic={topic}
        />
      )}
    </div>
  );
}
