"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { CircleList } from "@/components/CircleList";
import { ErrorNote, Loading } from "@/components/SignInPrompt";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { SourceSummary } from "@/lib/types";

export function CirclesView() {
  const { ready, user } = useAuth();
  const params = useSearchParams();
  const source = params.get("source") ?? "";
  return (
    <div className="mx-auto max-w-3xl">
      <header className="mx-auto max-w-read text-center">
        <h1 className="font-serif text-4xl font-semibold tracking-tight">Book circles</h1>
        <p className="mt-3 text-lg text-muted">
          Small groups reading one book together. Join one, or start a circle from any book&apos;s page.
        </p>
      </header>
      {ready && user ? <MyCircles /> : null}
      <Browse source={source} />
    </div>
  );
}

function MyCircles() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.circles({ mine: true }).then((r) => r.circles), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad(loader);
  return (
    <section aria-labelledby="mine-title" className="mt-10">
      <h2 id="mine-title" className="font-serif text-2xl font-semibold">
        Your circles
      </h2>
      <div className="mt-4">
        {loading ? (
          <Loading />
        ) : error ? (
          <ErrorNote error={error} />
        ) : data?.length ? (
          <CircleList circles={data} />
        ) : (
          <p className="text-muted">You haven&apos;t joined any circles yet.</p>
        )}
      </div>
    </section>
  );
}

async function allSources(api: ReturnType<typeof useAuth>["api"]): Promise<SourceSummary[]> {
  const out: SourceSummary[] = [];
  let cursor: string | null = null;
  do {
    const page = await api.sources({ cursor, limit: 50 });
    out.push(...page.sources);
    cursor = page.next_cursor;
  } while (cursor && out.length < 500);
  return out;
}

function Browse({ source }: { source: string }) {
  const { api, token } = useAuth();
  const router = useRouter();
  const loader = useCallback(
    () => api.circles({ source: source || undefined, limit: 60 }).then((r) => r.circles),
    [api, source, token], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const { data, error, loading } = useLoad(loader);
  const sourcesLoader = useCallback(() => allSources(api), [api]);
  const { data: sources } = useLoad(sourcesLoader);
  const book = sources?.find((s) => s.id === source);

  return (
    <section aria-labelledby="browse-title" className="mt-12">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h2 id="browse-title" className="font-serif text-2xl font-semibold">
          {book ? `Circles for ${book.title}` : "Browse circles"}
        </h2>
        <div>
          <label htmlFor="circle-book" className="sr-only">
            Filter by book
          </label>
          <select
            id="circle-book"
            className="field min-h-10 py-1 text-sm pointer-coarse:min-h-11"
            value={source}
            onChange={(e) => router.replace(e.target.value ? `/circles?source=${encodeURIComponent(e.target.value)}` : "/circles")}
          >
            <option value="">All books</option>
            {(sources ?? []).map((s) => (
              <option key={s.id} value={s.id}>
                {s.title}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div className="mt-4">
        {loading ? (
          <Loading />
        ) : error ? (
          <ErrorNote error={error} />
        ) : data?.length ? (
          <CircleList circles={data} showBook={!source} />
        ) : (
          <p className="text-muted">
            No circles here yet.{" "}
            {source ? (
              <Link href={`/sources/${source}#circles`} className="link">
                Start one for this book
              </Link>
            ) : (
              <>
                Start one from any{" "}
                <Link href="/sources" className="link">
                  book&apos;s page
                </Link>
              </>
            )}
            .
          </p>
        )}
      </div>
    </section>
  );
}
