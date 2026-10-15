"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { VisibilityBadge } from "@/components/VisibilityBadge";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { topicName } from "@/lib/content";
import { useLoad } from "@/lib/use-load";
import type { Card, MemberCategory } from "@/lib/types";

export function MyCardsView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">My cards</h1>
      <p className="mt-2 text-muted">
        Write your own ideas. Choose who sees each one, file them under your own categories, and add a picture, audio or
        a video in the card studio.
      </p>
      <div className="mt-4 flex flex-wrap gap-2">
        <Link href="/me/cards/new" className="btn btn-primary">
          Write a card
        </Link>
        <Link href="/me/earnings" className="btn">
          Earnings
        </Link>
      </div>
      <div className="mt-8">
        <RequireAuth message="Sign in to write your own cards.">
          <MyCards />
        </RequireAuth>
      </div>
    </div>
  );
}

/** What a card has from the studio, as short labels. */
function mediaLabels(c: Card): string[] {
  return [c.image ? "Picture" : "", c.audio ? "Audio" : "", c.video ? "Video" : ""].filter(Boolean);
}

function MyCards() {
  const { api, token } = useAuth();
  // "" is every card, "none" the ones without a category.
  const [category, setCategory] = useState("");
  const catLoader = useCallback(() => api.myCategories().then((r) => r.categories), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const cats = useLoad<MemberCategory[]>(catLoader);
  const loader = useCallback(
    () => api.myCards({ category: category || undefined, limit: 50 }),
    [api, category, token], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const { data, error, loading, setData } = useLoad(loader);
  const [more, setMore] = useState<{ busy: boolean; error: string | null }>({ busy: false, error: null });

  async function loadMore() {
    if (!data?.next_cursor) return;
    setMore({ busy: true, error: null });
    try {
      const page = await api.myCards({ category: category || undefined, cursor: data.next_cursor, limit: 50 });
      setData((d) => ({ cards: [...(d?.cards ?? []), ...page.cards], next_cursor: page.next_cursor }));
      setMore({ busy: false, error: null });
    } catch (err) {
      setMore({ busy: false, error: isApiError(err) ? err.message : "Couldn't load more." });
    }
  }

  const categories = cats.data ?? [];
  const chips = [{ id: "", name: "All" }, ...categories, ...(categories.length ? [{ id: "none", name: "No category" }] : [])];

  return (
    <>
      {chips.length > 1 ? (
        <div role="group" aria-label="Filter by category" className="flex flex-wrap gap-2">
          {chips.map((c) => (
            <button
              key={c.id || "all"}
              type="button"
              aria-pressed={category === c.id}
              className={`chip min-h-9 pointer-coarse:min-h-11 ${category === c.id ? "chip-on" : "hover:text-fg"}`}
              onClick={() => setCategory(c.id)}
            >
              {c.name}
            </button>
          ))}
        </div>
      ) : null}

      <div className="mt-6">
        {loading ? (
          <Loading label="Loading your cards…" />
        ) : error ? (
          <ErrorNote error={error} />
        ) : !data?.cards.length ? (
          <p className="panel p-6 text-center text-muted">
            {category ? (
              "No cards here."
            ) : (
              <>
                You haven&apos;t written any cards yet.{" "}
                <Link href="/me/cards/new" className="link">
                  Write your first
                </Link>
              </>
            )}
          </p>
        ) : (
          <ul className="grid gap-3">
            {data.cards.map((c) => (
              <li key={c.id} className="panel relative p-5 hover:border-accent">
                <div className="flex items-start justify-between gap-3">
                  <h2 className="min-w-0 font-serif text-xl font-semibold">
                    <Link href={`/me/cards/${c.id}`} className="after:absolute after:inset-0 hover:underline">
                      {c.title}
                    </Link>
                  </h2>
                  <VisibilityBadge visibility={c.visibility} />
                </div>
                <p className="mt-2 text-sm text-muted">
                  {[topicName(c.topic), c.category?.name, ...mediaLabels(c)].filter(Boolean).join(" · ")}
                </p>
              </li>
            ))}
          </ul>
        )}
        {data?.next_cursor ? (
          <div className="mt-4 text-center">
            <button type="button" className="btn" onClick={loadMore} disabled={more.busy}>
              {more.busy ? "Loading…" : "Load more"}
            </button>
            <ErrorNote error={more.error} />
          </div>
        ) : null}
      </div>

      <Categories
        categories={categories}
        loading={cats.loading}
        onChange={(next) => {
          cats.setData(() => next);
          if (category && category !== "none" && !next.some((c) => c.id === category)) setCategory("");
        }}
      />
    </>
  );
}

/** Create, rename and delete my categories. Deleting one keeps its cards, uncategorised. */
function Categories({
  categories,
  loading,
  onChange,
}: {
  categories: MemberCategory[];
  loading: boolean;
  onChange: (next: MemberCategory[]) => void;
}) {
  const { api } = useAuth();
  const [name, setName] = useState("");
  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function act(fn: () => Promise<void>, fallback: string) {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (err) {
      setError(
        isApiError(err) && err.status === 409 ? "You already have a category with that name." : isApiError(err) ? err.message : fallback,
      );
    } finally {
      setBusy(false);
    }
  }

  const create = (e: React.FormEvent) => {
    e.preventDefault();
    const n = name.trim();
    if (!n) return;
    return act(async () => {
      const c = await api.createCategory(n);
      onChange([...categories, c].sort((a, b) => a.name.localeCompare(b.name)));
      setName("");
    }, "Couldn't add the category.");
  };

  const rename = (e: React.FormEvent) => {
    e.preventDefault();
    if (!editing?.name.trim()) return;
    const { id, name: n } = editing;
    return act(async () => {
      const c = await api.renameCategory(id, n.trim());
      onChange(categories.map((o) => (o.id === id ? { ...o, name: c.name } : o)));
      setEditing(null);
    }, "Couldn't rename the category.");
  };

  const remove = (c: MemberCategory) => {
    if (!window.confirm(`Delete “${c.name}”? Its cards stay, without a category.`)) return;
    return act(async () => {
      await api.deleteCategory(c.id);
      onChange(categories.filter((o) => o.id !== c.id));
    }, "Couldn't delete the category.");
  };

  return (
    <section aria-labelledby="categories-title" className="mt-12">
      <h2 id="categories-title" className="font-serif text-2xl font-semibold">
        Categories
      </h2>
      <p className="mt-1 text-sm text-muted">Your own shelves for your cards. Readers can filter your page by them.</p>
      {loading ? (
        <Loading />
      ) : categories.length ? (
        <ul className="mt-4 divide-y divide-line rounded-xl border border-line">
          {categories.map((c) => (
            <li key={c.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2">
              {editing?.id === c.id ? (
                <form onSubmit={rename} className="flex w-full gap-2">
                  <label htmlFor={`cat-${c.id}`} className="sr-only">
                    New name for {c.name}
                  </label>
                  <input
                    id={`cat-${c.id}`}
                    className="field"
                    maxLength={40}
                    value={editing.name}
                    onChange={(e) => setEditing({ id: c.id, name: e.target.value })}
                  />
                  <button type="submit" className="btn btn-primary shrink-0" disabled={busy || !editing.name.trim()}>
                    Save
                  </button>
                  <button type="button" className="btn shrink-0" onClick={() => setEditing(null)}>
                    Cancel
                  </button>
                </form>
              ) : (
                <>
                  <span className="min-w-0">
                    <span className="font-medium">{c.name}</span>{" "}
                    <span className="text-sm text-muted">
                      · {c.card_count ?? 0} {c.card_count === 1 ? "card" : "cards"}
                    </span>
                  </span>
                  <span className="flex gap-1">
                    <button type="button" className="btn btn-small btn-ghost" disabled={busy} onClick={() => setEditing({ id: c.id, name: c.name })}>
                      Rename<span className="sr-only"> {c.name}</span>
                    </button>
                    <button type="button" className="btn btn-small btn-ghost text-bad" disabled={busy} onClick={() => remove(c)}>
                      Delete<span className="sr-only"> {c.name}</span>
                    </button>
                  </span>
                </>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-3 text-muted">No categories yet.</p>
      )}
      <form onSubmit={create} className="mt-4 flex gap-2">
        <label htmlFor="new-category" className="sr-only">
          New category name
        </label>
        <input
          id="new-category"
          className="field"
          placeholder="New category, e.g. Morning habits"
          maxLength={40}
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button type="submit" className="btn btn-primary shrink-0" disabled={busy || !name.trim()}>
          Add
        </button>
      </form>
      <ErrorNote error={error} />
    </section>
  );
}
