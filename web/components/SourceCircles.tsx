"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import { CircleList } from "./CircleList";
import { ErrorNote, Loading, useSignInRedirect } from "./SignInPrompt";

/** "Circles" section on a source page: the book's circles and a form to start one. */
export function SourceCircles({ sourceId, title }: { sourceId: string; title: string }) {
  const { api, token, user } = useAuth();
  const router = useRouter();
  const toSignIn = useSignInRedirect();
  const loader = useCallback(() => api.circles({ source: sourceId }).then((r) => r.circles), [api, sourceId, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad(loader);
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    setFormError(null);
    try {
      const c = await api.createCircle({ source_id: sourceId, name: name.trim(), description: description.trim() || undefined });
      router.push(`/circles/${c.id}`);
    } catch (err) {
      setFormError(
        isApiError(err) && err.status === 429
          ? "You've started a lot of circles today. Try again tomorrow."
          : isApiError(err)
            ? err.message
            : "Couldn't start the circle.",
      );
      setBusy(false);
    }
  }

  return (
    <section id="circles" aria-labelledby="circles-title" className="mt-12 scroll-mt-24">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h2 id="circles-title" className="font-serif text-2xl font-semibold">
          Circles
        </h2>
        {!open ? (
          <button type="button" className="btn btn-small" onClick={() => (user ? setOpen(true) : toSignIn())}>
            Start a circle
          </button>
        ) : null}
      </div>
      <p className="mt-1 text-sm text-muted">Read {title} with up to 50 others and talk about it as you go.</p>
      {open ? (
        <form onSubmit={create} className="panel mt-4 space-y-3 p-5">
          <div>
            <label htmlFor="circle-name" className="label">
              Circle name
            </label>
            <input
              id="circle-name"
              className="field"
              required
              maxLength={80}
              placeholder={`e.g. Reading ${title} in October`}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div>
            <label htmlFor="circle-desc" className="label">
              Description <span className="font-normal text-muted">(optional)</span>
            </label>
            <textarea
              id="circle-desc"
              className="field min-h-20"
              maxLength={500}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <ErrorNote error={formError} />
          <div className="flex gap-2">
            <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
              {busy ? "Starting…" : "Start circle"}
            </button>
            <button type="button" className="btn" onClick={() => setOpen(false)}>
              Cancel
            </button>
          </div>
        </form>
      ) : null}
      <div className="mt-4">
        {loading ? (
          <Loading label="Loading circles…" />
        ) : error ? (
          <ErrorNote error={error} />
        ) : data?.length ? (
          <CircleList circles={data} showBook={false} />
        ) : (
          <p className="text-muted">No circles for this book yet.</p>
        )}
      </div>
      <p className="mt-3 text-sm">
        <Link href="/circles" className="link">
          All book circles
        </Link>
      </p>
    </section>
  );
}
