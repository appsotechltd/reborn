"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { licenceName, TOPICS, topicName } from "@/lib/content";
import { authorHref } from "@/lib/social";
import type { AuthorSummary, SourceSummary } from "@/lib/types";
import { AuthorLinks } from "./CardView";
import { ChipRow } from "./ChipRow";
import { Icon } from "./Icon";

/*
 * The Library: every book (/sources) and every author (/authors), searchable and filtered by topic.
 * The page renders the first page on the server (for search engines and a fast first paint); this
 * then searches, filters and pages in the browser, keeping the URL in step so it can be shared.
 */

export type LibraryKind = "books" | "authors";

const SEARCH_DELAY_MS = 300;
const PAGE = 50;

type Item<K extends LibraryKind> = K extends "books" ? SourceSummary : AuthorSummary;

export interface LibraryPage<K extends LibraryKind> {
  items: Item<K>[];
  cursor: string | null;
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** "Library" with its two tabs, shared by /sources and /authors. */
export function LibraryHeader({ current }: { current: LibraryKind }) {
  const tabs: { kind: LibraryKind; href: string; label: string }[] = [
    { kind: "books", href: "/sources", label: "Books" },
    { kind: "authors", href: "/authors", label: "Authors" },
  ];
  return (
    <header>
      <h1 className="font-serif text-4xl font-semibold tracking-tight max-md:text-3xl">Library</h1>
      <p className="mt-3 text-lg text-muted max-md:text-base">
        Every idea on Reborn comes from one of these works and links back to it. Pick a book or an author to see all
        of its ideas and videos.
      </p>
      <nav aria-label="Library" className="mt-6 flex gap-1 border-b border-line">
        {tabs.map((t) => {
          const on = t.kind === current;
          return (
            <Link
              key={t.kind}
              href={t.href}
              aria-current={on ? "page" : undefined}
              className={`-mb-px inline-flex min-h-11 items-center border-b-2 px-4 ${
                on ? "border-accent font-semibold text-fg" : "border-transparent text-muted hover:text-fg"
              }`}
            >
              {t.label}
            </Link>
          );
        })}
      </nav>
    </header>
  );
}

/** A small "N videos" marker, shown only when there are some. */
export function VideoCount({ count }: { count: number | undefined }) {
  if (!count) return null;
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-accent-soft px-2 py-0.5 text-xs font-semibold text-accent-text">
      <Icon name="play" className="size-3.5" />
      {plural(count, "video", "videos")}
    </span>
  );
}

export function BookRow({ source: s }: { source: SourceSummary }) {
  return (
    <li className="py-5">
      <h2 className="font-serif text-xl font-semibold">
        <Link href={`/sources/${s.id}`} className="inline-flex items-center hover:underline pointer-coarse:min-h-11">
          {s.title}
        </Link>
      </h2>
      <p className="mt-1 text-muted">
        <AuthorLinks authors={s.authors} className="hover:text-fg hover:underline" /> ·{" "}
        <span className="capitalize">{s.kind}</span> · {licenceName(s.licence)}
      </p>
      <p className="mt-2 flex flex-wrap items-center gap-2 text-sm">
        <span className="text-muted">{plural(s.card_count, "idea", "ideas")}</span>
        <VideoCount count={s.video_count} />
        {s.topics.map((t) => (
          <Link key={t} href={`/topics/${t}`} className="chip hover:text-fg pointer-coarse:min-h-11">
            {topicName(t)}
          </Link>
        ))}
      </p>
    </li>
  );
}

export function AuthorRow({ author: a }: { author: AuthorSummary }) {
  return (
    <li className="relative flex items-center justify-between gap-4 py-4">
      <div className="min-w-0">
        <h2 className="font-serif text-xl font-semibold">
          <Link href={authorHref(a.name)} className="after:absolute after:inset-0 hover:underline">
            {a.name}
          </Link>
        </h2>
        <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted">
          <span>{plural(a.sources, "book", "books")}</span>
          <span aria-hidden="true">·</span>
          <span>{plural(a.card_count, "idea", "ideas")}</span>
          <VideoCount count={a.video_count} />
        </p>
      </div>
      <Icon name="chevronRight" className="size-5 shrink-0 text-muted" />
    </li>
  );
}

function libraryUrl(kind: LibraryKind, q: string, topic: string): string {
  const params = new URLSearchParams();
  if (q) params.set("q", q);
  if (topic) params.set("topic", topic);
  const qs = params.toString();
  return `${kind === "books" ? "/sources" : "/authors"}${qs ? `?${qs}` : ""}`;
}

export function LibraryBrowser<K extends LibraryKind>({
  kind,
  initial,
  initialQuery = "",
  initialTopic = "",
}: {
  kind: K;
  /** The first page, rendered on the server for these filters. */
  initial: LibraryPage<K>;
  initialQuery?: string;
  initialTopic?: string;
}) {
  const { api } = useAuth();
  const [q, setQ] = useState(initialQuery);
  const [topic, setTopic] = useState(initialTopic);
  // The list and the filters it was loaded for.
  const [page, setPage] = useState({ ...initial, filters: { q: initialQuery, topic: initialTopic } });
  const [loading, setLoading] = useState<"list" | "more" | null>(null);
  const [error, setError] = useState<string | null>(null);
  // The filters the list shows; a newer search drops older answers.
  const shown = useRef({ q: initialQuery, topic: initialTopic });
  const request = useRef(0);

  const noun = kind === "books" ? "books" : "authors";

  async function fetchPage(filters: { q: string; topic: string }, cursor: string | null): Promise<LibraryPage<K>> {
    const query = { q: filters.q || undefined, topic: filters.topic || undefined, cursor, limit: PAGE };
    if (kind === "books") {
      const r = await api.sources(query);
      return { items: r.sources as Item<K>[], cursor: r.next_cursor };
    }
    const r = await api.authors(query);
    return { items: r.authors as Item<K>[], cursor: r.next_cursor };
  }

  // Search as the reader types (debounced) and whenever the topic changes.
  useEffect(() => {
    const filters = { q: q.trim(), topic };
    if (filters.q === shown.current.q && filters.topic === shown.current.topic) return;
    const id = ++request.current;
    const timer = setTimeout(
      async () => {
        setLoading("list");
        setError(null);
        try {
          const next = await fetchPage(filters, null);
          if (id !== request.current) return;
          shown.current = filters;
          setPage({ ...next, filters });
          try {
            window.history.replaceState(window.history.state, "", libraryUrl(kind, filters.q, filters.topic));
          } catch {
            // Some embedded browsers refuse history changes: the list still updates.
          }
        } catch (err) {
          if (id !== request.current) return;
          setError(isApiError(err) && err.status > 0 && err.status < 500 ? err.message : `Couldn't load the ${noun}.`);
        } finally {
          if (id === request.current) setLoading(null);
        }
      },
      filters.q === shown.current.q ? 0 : SEARCH_DELAY_MS,
    );
    return () => clearTimeout(timer);
    // fetchPage only reads props and the stable api client.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, topic]);

  async function more() {
    if (!page.cursor || loading) return;
    const id = request.current;
    setLoading("more");
    setError(null);
    try {
      const next = await fetchPage(page.filters, page.cursor);
      if (id !== request.current) return;
      setPage((p) => {
        const have = new Set(p.items.map(key));
        return { ...p, items: [...p.items, ...next.items.filter((i) => !have.has(key(i)))], cursor: next.cursor };
      });
    } catch {
      if (id === request.current) setError(`Couldn't load more ${noun}.`);
    } finally {
      if (id === request.current) setLoading(null);
    }
  }

  const filtered = !!(page.filters.q || page.filters.topic);
  const label = kind === "books" ? "Search books by title or author" : "Search authors by name";

  return (
    <div className="mt-6">
      <form role="search" onSubmit={(e) => e.preventDefault()}>
        <label htmlFor={`library-q-${kind}`} className="sr-only">
          {label}
        </label>
        <div className="relative">
          <Icon
            name="search"
            className="pointer-events-none absolute left-3.5 top-1/2 size-5 -translate-y-1/2 text-muted"
          />
          <input
            id={`library-q-${kind}`}
            type="search"
            value={q}
            onChange={(e) => setQ(e.currentTarget.value)}
            placeholder={kind === "books" ? "Search books or authors" : "Search authors"}
            autoComplete="off"
            className="field pl-11"
          />
        </div>
      </form>

      <ChipRow
        label={`Filter ${noun} by topic`}
        className="mt-4 max-md:-mx-4"
        scrollClassName="flex flex-wrap gap-2 max-md:flex-nowrap max-md:overflow-x-auto max-md:px-4 max-md:pb-1 max-md:[scrollbar-width:none]"
      >
        {[{ slug: "", name: "All topics" }, ...TOPICS].map((t) => (
          <button
            key={t.slug}
            type="button"
            aria-pressed={topic === t.slug}
            onClick={() => setTopic(t.slug)}
            className={`chip min-h-8 shrink-0 pointer-coarse:min-h-11 ${topic === t.slug ? "chip-on" : "hover:text-fg"}`}
          >
            {t.name}
          </button>
        ))}
      </ChipRow>

      {error ? (
        <p role="alert" className="mt-4 text-bad">
          {error}
        </p>
      ) : null}

      <div aria-live="polite" aria-busy={loading === "list"} className={loading === "list" ? "opacity-60" : undefined}>
        {page.items.length === 0 ? (
          <p className="mt-8 text-muted">
            {filtered ? `No ${noun} match. Try another word or topic.` : `No ${noun} have been published yet.`}
          </p>
        ) : (
          <ul aria-label={kind === "books" ? "Books" : "Authors"} className="mt-6 divide-y divide-line border-y border-line">
            {page.items.map((item) =>
              kind === "books" ? (
                <BookRow key={key(item)} source={item as SourceSummary} />
              ) : (
                <AuthorRow key={key(item)} author={item as AuthorSummary} />
              ),
            )}
          </ul>
        )}
      </div>

      {page.cursor ? (
        <div className="mt-6 text-center">
          <button type="button" className="btn" onClick={more} disabled={!!loading}>
            {loading === "more" ? "Loading…" : `Load more ${noun}`}
          </button>
        </div>
      ) : null}
    </div>
  );
}

function key(item: SourceSummary | AuthorSummary): string {
  return "id" in item ? item.id : item.name;
}
