import type { Metadata } from "next";
import { LibraryHeader } from "@/components/Library";
import { SummaryPost } from "@/components/SummaryPost";
import { Unavailable } from "@/components/Unavailable";
import { getAllSummaries, loadOr } from "@/lib/server-api";
import { DEFAULT_OG_IMAGE } from "@/lib/config";

export const revalidate = 600;

const description =
  "Whole books and topics, one part at a time: swipe through the ideas, read them all on one page, or listen start to finish.";

export const metadata: Metadata = {
  title: "Summaries",
  description,
  alternates: { canonical: "/summaries" },
  openGraph: { siteName: "Reborn", title: "Summaries", description, url: "/summaries", images: [DEFAULT_OG_IMAGE] },
  twitter: { card: "summary_large_image", title: "Summaries", description, images: [DEFAULT_OG_IMAGE] },
};

export default async function SummariesPage() {
  const { data, ok } = await loadOr(() => getAllSummaries(), null);
  const topics = data?.filter((s) => s.kind === "topic") ?? [];
  const books = data?.filter((s) => s.kind === "book") ?? [];
  return (
    <div className="mx-auto max-w-3xl">
      <LibraryHeader current="summaries" />
      {!ok || !data ? (
        <div className="mt-8">
          <Unavailable what="the summaries" />
        </div>
      ) : (
        <>
          {topics.length ? (
            <section aria-labelledby="topic-summaries" className="mt-8">
              <h2 id="topic-summaries" className="font-serif text-2xl font-semibold">
                Topics
              </h2>
              <p className="mt-1 text-muted">The best ideas on one subject, from several books.</p>
              <ul className="mt-4 grid gap-6">
                {topics.map((s) => (
                  <li key={s.id}>
                    <SummaryPost summary={s} />
                  </li>
                ))}
              </ul>
            </section>
          ) : null}
          <section aria-labelledby="book-summaries" className="mt-12">
            <h2 id="book-summaries" className="font-serif text-2xl font-semibold">
              Books
            </h2>
            <p className="mt-1 text-muted">Every book with five or more ideas, from start to finish.</p>
            <ul className="mt-4 grid gap-6">
              {books.map((s) => (
                <li key={s.id}>
                  <SummaryPost summary={s} />
                </li>
              ))}
            </ul>
          </section>
        </>
      )}
    </div>
  );
}
