"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { authorHref } from "@/lib/social";
import { useLoad } from "@/lib/use-load";
import type { FollowingItem, FollowKind } from "@/lib/types";

const GROUPS: { kind: FollowKind; title: string; empty: string }[] = [
  { kind: "user", title: "People", empty: "You're not following anyone yet. Follow people from their profile." },
  { kind: "author", title: "Authors", empty: "Follow an author from their page to see their ideas first." },
  { kind: "source", title: "Books and sources", empty: "Follow a book from its source page." },
];

function href(item: FollowingItem): string {
  if (item.kind === "user") return `/u/${item.handle ?? ""}`;
  if (item.kind === "author") return authorHref(item.target);
  return `/sources/${item.target}`;
}

export function FollowingView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Following</h1>
      <p className="mt-2 text-muted">
        The people, authors and books that shape your timeline.
      </p>
      <div className="mt-8">
        <RequireAuth message="Sign in to follow people, authors and books.">
          <FollowingList />
        </RequireAuth>
      </div>
    </div>
  );
}

function FollowingList() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.following().then((r) => r.following), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, setData } = useLoad(loader);
  const [busy, setBusy] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  if (loading) return <Loading />;
  if (error) return <ErrorNote error={error} />;

  async function unfollow(item: FollowingItem) {
    const key = `${item.kind}:${item.target}`;
    setBusy(key);
    setActionError(null);
    try {
      await api.setFollow(item.kind, item.target, false);
      setData((prev) => (prev ?? []).filter((f) => !(f.kind === item.kind && f.target === item.target)));
    } catch (err) {
      setActionError(isApiError(err) ? err.message : "Couldn't unfollow. Please try again.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-10">
      <ErrorNote error={actionError} />
      {GROUPS.map((g) => {
        const items = (data ?? []).filter((f) => f.kind === g.kind);
        return (
          <section key={g.kind} aria-labelledby={`following-${g.kind}`}>
            <h2 id={`following-${g.kind}`} className="font-serif text-2xl font-semibold">
              {g.title} <span className="text-muted">({items.length})</span>
            </h2>
            {items.length === 0 ? (
              <p className="mt-3 text-muted">{g.empty}</p>
            ) : (
              <ul className="mt-3 divide-y divide-line border-y border-line">
                {items.map((f) => (
                  <li key={f.target} className="flex items-center justify-between gap-3 py-3">
                    <span className="min-w-0">
                      <Link href={href(f)} className="font-semibold hover:underline">
                        {f.label}
                      </Link>
                      {f.handle ? <span className="text-muted"> @{f.handle}</span> : null}
                    </span>
                    <button
                      type="button"
                      className="btn btn-small shrink-0"
                      disabled={busy !== null}
                      onClick={() => unfollow(f)}
                    >
                      {busy === `${f.kind}:${f.target}` ? "…" : "Unfollow"}
                      <span className="sr-only"> {f.label}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>
        );
      })}
    </div>
  );
}
