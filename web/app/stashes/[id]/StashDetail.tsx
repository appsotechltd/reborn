"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { Card, Stash } from "@/lib/types";

export function StashDetail({ id, publicHref }: { id: string; publicHref?: string }) {
  const { ready, user } = useAuth();
  return (
    <div className="mx-auto max-w-read">
      <p>
        <Link href="/stashes" className="link text-sm">
          ← All stashes
        </Link>
      </p>
      <div className="mt-4">
        <RequireAuth message="Stashes are private to the account that made them. Sign in to open this one.">
          <StashBody id={id} />
        </RequireAuth>
        {ready && !user && publicHref ? (
          <p className="mt-4 text-center text-sm text-muted">
            Its owner has shared it.{" "}
            <Link href={publicHref} className="link">
              Read the public stash
            </Link>
          </p>
        ) : null}
      </div>
    </div>
  );
}

function StashBody({ id }: { id: string }) {
  const { api, token } = useAuth();
  const router = useRouter();
  const loader = useCallback(() => api.stash(id), [api, id, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, status, loading, setData } = useLoad<{ stash: Stash; cards: Card[] }>(loader);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  if (loading) return <Loading />;
  if (status === 404) {
    return (
      <div>
        <h1 className="font-serif text-3xl font-semibold">Stash not found</h1>
        <p className="mt-2 text-muted">It may have been deleted.</p>
      </div>
    );
  }
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load this stash."} />;

  const { stash, cards } = data;

  async function act(fn: () => Promise<void>, fallback: string) {
    setBusy(true);
    setActionError(null);
    try {
      await fn();
    } catch (err) {
      setActionError(isApiError(err) ? err.message : fallback);
    } finally {
      setBusy(false);
    }
  }

  const save = (e: React.FormEvent) => {
    e.preventDefault();
    return act(async () => {
      const updated = await api.updateStash(stash.id, { name: name.trim(), description: description.trim() });
      setData((d) => ({ stash: updated, cards: d?.cards ?? [] }));
      setEditing(false);
    }, "Couldn't rename the stash.");
  };

  const togglePublic = (on: boolean) =>
    act(async () => {
      setData((d) => ({ stash: { ...stash, is_public: on }, cards: d?.cards ?? [] }));
      try {
        const updated = await api.updateStash(stash.id, { is_public: on });
        setData((d) => ({ stash: updated, cards: d?.cards ?? [] }));
      } catch (err) {
        setData((d) => ({ stash: { ...stash, is_public: !on }, cards: d?.cards ?? [] }));
        throw err;
      }
    }, "Couldn't change who can see this stash.");

  const remove = () => {
    if (!window.confirm(`Delete “${stash.name}”? The ideas stay in the library.`)) return;
    return act(async () => {
      await api.deleteStash(stash.id);
      router.push("/stashes");
    }, "Couldn't delete the stash.");
  };

  const removeCard = (card: Card) =>
    act(async () => {
      await api.removeFromStash(stash.id, card.id);
      setData((d) => ({
        stash: { ...stash, card_count: Math.max(0, stash.card_count - 1) },
        cards: (d?.cards ?? []).filter((c) => c.id !== card.id),
      }));
    }, "Couldn't remove the idea.");

  return (
    <>
      {editing ? (
        <form onSubmit={save} className="panel space-y-3 p-5">
          <div>
            <label htmlFor="edit-name" className="label">
              Name
            </label>
            <input
              id="edit-name"
              className="field"
              required
              maxLength={80}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div>
            <label htmlFor="edit-desc" className="label">
              Description
            </label>
            <input
              id="edit-desc"
              className="field"
              maxLength={280}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="flex gap-2">
            <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
              Save
            </button>
            <button type="button" className="btn" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </div>
        </form>
      ) : (
        <header>
          <h1 className="font-serif text-4xl font-semibold tracking-tight">{stash.name}</h1>
          {stash.description ? <p className="mt-2 text-lg text-muted">{stash.description}</p> : null}
          <div className="mt-4 flex flex-wrap gap-2">
            <button
              type="button"
              className="btn btn-small"
              onClick={() => {
                setName(stash.name);
                setDescription(stash.description);
                setEditing(true);
              }}
            >
              Rename
            </button>
            <button type="button" className="btn btn-small" onClick={remove} disabled={busy}>
              Delete stash
            </button>
          </div>
          <div className="panel mt-4 flex flex-wrap items-center justify-between gap-3 p-4">
            <label className="flex cursor-pointer items-center gap-3">
              <input
                type="checkbox"
                className="size-4"
                checked={!!stash.is_public}
                disabled={busy}
                onChange={(e) => togglePublic(e.target.checked)}
              />
              <span>
                <span className="font-semibold">Public</span>
                <span className="block text-sm text-muted">
                  {stash.is_public ? "Anyone with the link can see it, and it shows on your profile." : "Only you can see this stash."}
                </span>
              </span>
            </label>
            {stash.is_public ? (
              <Link href={`/s/${stash.id}`} className="link text-sm">
                View public page
              </Link>
            ) : null}
          </div>
        </header>
      )}
      <ErrorNote error={actionError} />

      <section aria-labelledby="stash-cards" className="mt-8">
        <h2 id="stash-cards" className="font-serif text-xl font-semibold">
          {cards.length} {cards.length === 1 ? "idea" : "ideas"}
        </h2>
        {cards.length === 0 ? (
          <p className="mt-3 text-muted">
            Nothing here yet. Open any idea and press <strong>Stash</strong> to add it.
          </p>
        ) : (
          <ul className="mt-4 grid gap-3">
            {cards.map((c) => (
              <li key={c.id} className="panel flex items-start justify-between gap-4 p-4">
                <div className="min-w-0">
                  <Link href={`/ideas/${c.id}`} className="font-serif text-lg font-semibold hover:underline">
                    {c.title}
                  </Link>
                  <p className="mt-1 text-xs text-muted">{c.credit}</p>
                </div>
                <button
                  type="button"
                  className="btn btn-small shrink-0"
                  onClick={() => removeCard(c)}
                  disabled={busy}
                >
                  Remove<span className="sr-only"> {c.title}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
