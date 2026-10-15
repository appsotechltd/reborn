"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { Stash } from "@/lib/types";
import { Icon } from "./Icon";

const ICON_CLASS = "btn btn-small btn-ghost px-2.5 text-muted hover:text-fg";

/**
 * "Save" a card to a collection (stashes in the API): pick one or create one. Prompts sign-in when signed out.
 * With `icon`, it is the bookmark in a post's action bar (as in the app) instead of a labelled button.
 */
export function StashButton({ cardId, cardTitle, icon = false }: { cardId: string; cardTitle: string; icon?: boolean }) {
  const { ready, user, api } = useAuth();
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [stashes, setStashes] = useState<Stash[] | null>(null);
  const [saved, setSaved] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [newName, setNewName] = useState("");

  if (!ready) {
    return icon ? (
      <button type="button" className={ICON_CLASS} disabled aria-label="Save to a collection">
        <Icon name="bookmarkBorder" />
      </button>
    ) : (
      <button type="button" className="btn btn-small" disabled>
        Save
      </button>
    );
  }

  if (!user) {
    return icon ? (
      <Link
        href={`/signin?next=${encodeURIComponent(`/ideas/${cardId}`)}`}
        className={ICON_CLASS}
        aria-label="Save to a collection (sign in to save this idea)"
      >
        <Icon name="bookmarkBorder" />
      </Link>
    ) : (
      <Link href={`/signin?next=${encodeURIComponent(`/ideas/${cardId}`)}`} className="btn btn-small">
        <span aria-hidden="true">＋</span> Save
        <span className="sr-only"> to a collection (sign in to save this idea)</span>
      </Link>
    );
  }

  async function open() {
    setError(null);
    dialogRef.current?.showModal();
    try {
      const res = await api.stashes();
      setStashes(res.stashes);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load your collections.");
      setStashes([]);
    }
  }

  async function add(stash: Stash) {
    setBusy(stash.id);
    setError(null);
    try {
      await api.addToStash(stash.id, cardId);
      setSaved((s) => new Set(s).add(stash.id));
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't save the card.");
    } finally {
      setBusy(null);
    }
  }

  async function create(e: React.FormEvent) {
    e.preventDefault();
    const name = newName.trim();
    if (!name) return;
    setBusy("new");
    setError(null);
    try {
      const stash = await api.createStash({ name });
      await api.addToStash(stash.id, cardId);
      setStashes((s) => [{ ...stash, card_count: stash.card_count + 1 }, ...(s ?? [])]);
      setSaved((s) => new Set(s).add(stash.id));
      setNewName("");
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't create the collection.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      {icon ? (
        <button
          type="button"
          className={saved.size ? "btn btn-small btn-ghost px-2.5 text-accent-text" : ICON_CLASS}
          onClick={open}
          aria-haspopup="dialog"
          aria-label={saved.size ? "Saved to a collection" : "Save to a collection"}
          title="Save to a collection"
        >
          <Icon name={saved.size ? "bookmark" : "bookmarkBorder"} />
        </button>
      ) : (
        <button type="button" className="btn btn-small" onClick={open} aria-haspopup="dialog">
          <span aria-hidden="true">＋</span> Save
          <span className="sr-only"> to a collection</span>
        </button>
      )}
      <dialog
        ref={dialogRef}
        aria-labelledby={`stash-${cardId}-title`}
        className="m-auto w-[min(28rem,calc(100vw-2rem))] rounded-2xl border border-line bg-surface p-0 text-fg backdrop:bg-black/50"
        onClick={(e) => {
          if (e.target === dialogRef.current) dialogRef.current?.close();
        }}
      >
        <div className="p-5">
          <h2 id={`stash-${cardId}-title`} className="font-serif text-xl font-semibold">
            Save to collection
          </h2>
          <p className="mt-1 text-sm text-muted">“{cardTitle}”. Saved ideas also go into your review.</p>

          {stashes === null ? (
            <p role="status" className="mt-4 text-muted">
              Loading your collections…
            </p>
          ) : stashes.length === 0 ? (
            <p className="mt-4 text-muted">You don&apos;t have any collections yet. Create your first one below.</p>
          ) : (
            <ul className="mt-4 max-h-64 divide-y divide-line overflow-y-auto rounded-lg border border-line">
              {stashes.map((s) => (
                <li key={s.id} className="flex items-center justify-between gap-3 px-3 py-2">
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{s.name}</span>
                    <span className="text-xs text-muted">
                      {s.card_count} {s.card_count === 1 ? "idea" : "ideas"}
                    </span>
                  </span>
                  {saved.has(s.id) ? (
                    <span className="text-sm font-semibold text-ok" role="status">
                      Saved ✓
                    </span>
                  ) : (
                    <button
                      type="button"
                      className="btn btn-small"
                      onClick={() => add(s)}
                      disabled={busy !== null}
                    >
                      {busy === s.id ? "Saving…" : "Add"}
                      <span className="sr-only"> to {s.name}</span>
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}

          <form onSubmit={create} className="mt-4 flex gap-2">
            <label htmlFor={`stash-${cardId}-new`} className="sr-only">
              New collection name
            </label>
            <input
              id={`stash-${cardId}-new`}
              className="field"
              placeholder="New collection, e.g. Morning reads"
              value={newName}
              maxLength={80}
              onChange={(e) => setNewName(e.target.value)}
            />
            <button type="submit" className="btn btn-primary shrink-0" disabled={!newName.trim() || busy !== null}>
              {busy === "new" ? "Creating…" : "Create"}
            </button>
          </form>

          {error ? (
            <p role="alert" className="mt-3 text-sm text-bad">
              {error}
            </p>
          ) : null}

          <div className="mt-5 flex justify-between gap-2">
            <Link href="/stashes" className="link self-center text-sm">
              Manage collections
            </Link>
            <button type="button" className="btn" onClick={() => dialogRef.current?.close()}>
              Done
            </button>
          </div>
        </div>
      </dialog>
    </>
  );
}
