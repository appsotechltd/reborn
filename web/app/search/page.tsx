import type { Metadata } from "next";
import { CardList } from "@/components/CardPreview";
import { Unavailable } from "@/components/Unavailable";
import { isApiError } from "@/lib/api";
import { TOPICS, topicName } from "@/lib/content";
import { searchCards } from "@/lib/server-api";
import type { Card } from "@/lib/types";

function first(v: string | string[] | undefined): string {
  return (Array.isArray(v) ? v[0] : v)?.trim() ?? "";
}

export async function generateMetadata({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }): Promise<Metadata> {
  const q = first((await searchParams).q);
  return {
    title: q ? `Search: ${q}` : "Search",
    description: "Search one-minute ideas from books and open sources.",
    alternates: { canonical: "/search" },
    robots: { index: false, follow: true },
  };
}

export default async function SearchPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const q = first(sp.q);
  const topic = first(sp.topic);
  const validTopic = TOPICS.some((t) => t.slug === topic) ? topic : "";

  let cards: Card[] = [];
  let error: "unavailable" | string | null = null;
  if (q) {
    try {
      cards = await searchCards(q, validTopic || undefined);
    } catch (err) {
      error = isApiError(err) && err.status > 0 && err.status < 500 ? err.message : "unavailable";
    }
  }

  return (
    <div>
      <div className="mx-auto max-w-read">
        <h1 className="font-serif text-4xl font-semibold tracking-tight">Search</h1>
        <form action="/search" method="get" role="search" className="mt-6 grid gap-3 sm:grid-cols-[1fr_auto_auto]">
          <div>
            <label htmlFor="q" className="sr-only">
              Search ideas
            </label>
            <input
              id="q"
              name="q"
              type="search"
              defaultValue={q}
              placeholder="Try “sleep”, “anger” or “memory”"
              className="field"
              autoComplete="off"
            />
          </div>
          <div>
            <label htmlFor="topic" className="sr-only">
              Topic
            </label>
            <select id="topic" name="topic" defaultValue={validTopic} className="field">
              <option value="">All topics</option>
              {TOPICS.map((t) => (
                <option key={t.slug} value={t.slug}>
                  {t.name}
                </option>
              ))}
            </select>
          </div>
          <button type="submit" className="btn btn-primary">
            Search
          </button>
        </form>
      </div>

      <section aria-live="polite" className="mt-10">
        {!q ? (
          <p className="mx-auto max-w-read text-muted">Search titles, ideas and sources across the library.</p>
        ) : error === "unavailable" ? (
          <Unavailable what="search results" />
        ) : error ? (
          <p role="alert" className="mx-auto max-w-read text-bad">
            {error}
          </p>
        ) : (
          <>
            <h2 className="font-serif text-xl font-semibold">
              {cards.length === 0 ? "No ideas" : `${cards.length} ${cards.length === 1 ? "idea" : "ideas"}`} for “{q}”
              {validTopic ? ` in ${topicName(validTopic)}` : ""}
            </h2>
            {cards.length ? (
              <div className="mt-4">
                <CardList cards={cards} />
              </div>
            ) : (
              <p className="mt-2 text-muted">Try a different word, or remove the topic filter.</p>
            )}
          </>
        )}
      </section>
    </div>
  );
}
