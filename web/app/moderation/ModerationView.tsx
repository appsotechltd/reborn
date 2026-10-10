"use client";

import { useCallback, useState } from "react";
import { ContributionStatus } from "@/components/ContributionStatus";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { WordCounter } from "@/components/WordCounter";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatAuthors, paragraphs, topicName } from "@/lib/content";
import { useLoad } from "@/lib/use-load";
import type { Contribution } from "@/lib/types";

export function ModerationView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Moderation</h1>
      <p className="mt-2 text-muted">
        Check each contribution is in the contributor&apos;s own words, accurate, credited and kind.
      </p>
      <div className="mt-8">
        <RequireAuth>
          <ModeratorOnly />
        </RequireAuth>
      </div>
    </div>
  );
}

function ModeratorOnly() {
  const { user } = useAuth();
  if (user?.role !== "moderator") {
    return (
      <div className="panel p-6 text-center">
        <h2 className="font-serif text-2xl font-semibold">Moderators only</h2>
        <p className="mt-2 text-muted">Your account doesn&apos;t have moderator access.</p>
      </div>
    );
  }
  return <Queue />;
}

function Queue() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.moderationQueue().then((r) => r.contributions), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, setData } = useLoad(loader);
  const [decided, setDecided] = useState<Contribution[]>([]);

  if (loading) return <Loading label="Loading the queue…" />;
  if (error) return <ErrorNote error={error} />;

  const onDecided = (c: Contribution) => {
    setData((prev) => (prev ?? []).filter((p) => p.id !== c.id));
    setDecided((d) => [c, ...d]);
  };

  return (
    <>
      {!data?.length ? (
        <p className="panel p-6 text-center text-muted">The queue is empty. Nice.</p>
      ) : (
        <ul className="grid gap-6">
          {data.map((c) => (
            <QueueItem key={c.id} c={c} onDecided={onDecided} />
          ))}
        </ul>
      )}
      {decided.length ? (
        <section aria-labelledby="decided-title" className="mt-10">
          <h2 id="decided-title" className="font-serif text-xl font-semibold">Decided this session</h2>
          <ul className="mt-3 grid gap-2">
            {decided.map((c) => (
              <li key={c.id} className="flex items-center justify-between gap-3 text-sm">
                <span className="truncate">{c.title}</span>
                <ContributionStatus status={c.status} />
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </>
  );
}

function QueueItem({ c, onDecided }: { c: Contribution; onDecided: (c: Contribution) => void }) {
  const { api } = useAuth();
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function decide(kind: "approve" | "reject") {
    setError(null);
    if (kind === "reject" && !note.trim()) {
      setError("Add a note so the contributor knows why.");
      return;
    }
    setBusy(true);
    try {
      const res = kind === "approve" ? await api.approve(c.id, note.trim() || undefined) : await api.reject(c.id, note.trim());
      onDecided(res);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't save the decision.");
      setBusy(false);
    }
  }

  return (
    <li className="panel p-5">
      <p className="eyebrow">{topicName(c.topic)}</p>
      <h2 className="mt-1 font-serif text-2xl font-semibold">{c.title}</h2>
      <p className="mt-1 text-sm text-muted">
        <a href={c.source.url} className="link" target="_blank" rel="noopener noreferrer">{c.source.title}</a> by{" "}
        {formatAuthors(c.source.authors)} · <span className="capitalize">{c.source.kind}</span> · sent{" "}
        {new Date(c.created_at).toLocaleDateString()}
      </p>
      <div className="prose-reborn mt-4 text-base">
        {paragraphs(c.body).map((p, i) => <p key={i}>{p}</p>)}
      </div>
      <WordCounter text={c.body} />
      <div className="mt-4 rounded-lg border-l-4 border-apply-border bg-apply px-4 py-3 text-apply-fg">
        <strong>Apply it:</strong> {c.apply_it}
      </div>
      {c.quiz ? (
        <div className="mt-4 text-sm">
          <p className="font-semibold">Quiz: {c.quiz.question}</p>
          <ol className="mt-1 list-decimal pl-6">
            {c.quiz.options.map((o, i) => (
              <li key={i} className={i === c.quiz!.answer ? "font-semibold text-ok" : ""}>
                {o}{i === c.quiz!.answer ? " (correct)" : ""}
              </li>
            ))}
          </ol>
          {c.quiz.explanation ? <p className="mt-1 text-muted">{c.quiz.explanation}</p> : null}
        </div>
      ) : null}
      <div className="mt-5">
        <label htmlFor={`note-${c.id}`} className="label">
          Note to contributor <span className="font-normal text-muted">(required to reject)</span>
        </label>
        <textarea id={`note-${c.id}`} className="field min-h-20" value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
      <ErrorNote error={error} />
      <div className="mt-4 flex flex-wrap gap-2">
        <button type="button" className="btn btn-primary" disabled={busy} onClick={() => decide("approve")}>Approve</button>
        <button type="button" className="btn" disabled={busy} onClick={() => decide("reject")}>Reject</button>
      </div>
    </li>
  );
}
