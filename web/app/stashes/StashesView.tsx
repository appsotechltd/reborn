"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { Stash } from "@/lib/types";

export function StashesView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Your stashes</h1>
      <p className="mt-2 text-muted">Collections of ideas you want to keep. Stashed ideas join your review.</p>
      <div className="mt-8">
        <RequireAuth message="Sign in to keep stashes of the ideas you want to remember.">
          <StashList />
        </RequireAuth>
      </div>
    </div>
  );
}

function StashList() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.stashes().then((r) => r.stashes), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: stashes, error, loading, setData } = useLoad<Stash[]>(loader);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    setActionError(null);
    try {
      const stash = await api.createStash({ name: name.trim(), description: description.trim() || undefined });
      setData((prev) => [stash, ...(prev ?? [])]);
      setName("");
      setDescription("");
    } catch (err) {
      setActionError(isApiError(err) ? err.message : "Couldn't create the stash.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <form onSubmit={create} className="panel space-y-3 p-5" aria-labelledby="new-stash-title">
        <h2 id="new-stash-title" className="font-semibold">
          New stash
        </h2>
        <div>
          <label htmlFor="stash-name" className="label">
            Name
          </label>
          <input
            id="stash-name"
            className="field"
            required
            maxLength={80}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Morning reads"
          />
        </div>
        <div>
          <label htmlFor="stash-desc" className="label">
            Description <span className="font-normal text-muted">(optional)</span>
          </label>
          <input
            id="stash-desc"
            className="field"
            maxLength={280}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
        </div>
        <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
          {busy ? "Creating…" : "Create stash"}
        </button>
        <ErrorNote error={actionError} />
      </form>

      <div className="mt-8">
        {loading ? (
          <Loading label="Loading your stashes…" />
        ) : error ? (
          <ErrorNote error={error} />
        ) : !stashes?.length ? (
          <p className="text-muted">
            No stashes yet. Create one above, or press <strong>Stash</strong> on any idea.
          </p>
        ) : (
          <ul className="grid gap-3">
            {stashes.map((s) => (
              <li key={s.id} className="panel relative p-5 hover:border-accent">
                <h2 className="font-serif text-xl font-semibold">
                  <Link href={`/stashes/${s.id}`} className="after:absolute after:inset-0 hover:underline">
                    {s.name}
                  </Link>
                </h2>
                {s.description ? <p className="mt-1 text-muted">{s.description}</p> : null}
                <p className="mt-2 text-sm text-muted">
                  {s.card_count} {s.card_count === 1 ? "idea" : "ideas"}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </>
  );
}
