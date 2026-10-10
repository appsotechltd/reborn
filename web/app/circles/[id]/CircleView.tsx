"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { ErrorNote, Loading, useSignInRedirect } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatDate } from "@/lib/engage";
import { useLoad } from "@/lib/use-load";
import type { Circle } from "@/lib/types";
import { CircleThread } from "./CircleThread";

export function CircleView({ id }: { id: string }) {
  const { api, token, ready, user } = useAuth();
  const router = useRouter();
  const toSignIn = useSignInRedirect();
  const loader = useCallback(() => api.circle(id), [api, id, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: circle, error, status, loading, setData } = useLoad(ready ? loader : null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [confirmLeave, setConfirmLeave] = useState(false);

  if (!ready || loading) return <Loading />;
  if (status === 404) {
    return (
      <div className="mx-auto max-w-read py-12 text-center">
        <h1 className="font-serif text-3xl font-semibold">Circle not found</h1>
        <p className="mt-2 text-muted">It may have closed after its last member left.</p>
        <Link href="/circles" className="btn btn-primary mt-6">
          Browse circles
        </Link>
      </div>
    );
  }
  if (error || !circle) return <ErrorNote error={error ?? "Couldn't load this circle."} />;

  async function join() {
    if (!user) return toSignIn();
    setBusy(true);
    setActionError(null);
    try {
      const c = await api.joinCircle(id);
      setData(() => c);
    } catch (err) {
      setActionError(
        isApiError(err) && err.code === "circle_full"
          ? "This circle is full (50 members). Try another circle for this book, or start your own."
          : isApiError(err)
            ? err.message
            : "Couldn't join the circle.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function leave() {
    setBusy(true);
    setActionError(null);
    try {
      await api.leaveCircle(id);
      if (circle!.members <= 1) {
        router.push("/circles");
        return;
      }
      setData((c) => ({ ...(c as Circle), is_member: false, role: null, members: Math.max(0, (c as Circle).members - 1) }));
      setConfirmLeave(false);
    } catch (err) {
      setActionError(isApiError(err) ? err.message : "Couldn't leave the circle.");
    } finally {
      setBusy(false);
    }
  }

  const full = circle.members >= 50;

  return (
    <div className="mx-auto max-w-read">
      <p>
        <Link href="/circles" className="link text-sm">
          ← All circles
        </Link>
      </p>
      <header className="mt-4">
        <p className="eyebrow">
          <Link href={`/sources/${circle.source.id}`} className="hover:text-accent hover:underline">
            {circle.source.title}
          </Link>
        </p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight text-balance">{circle.name}</h1>
        {circle.description ? <p className="mt-2 whitespace-pre-line text-lg text-muted">{circle.description}</p> : null}
        <p className="mt-3 text-sm text-muted">
          {circle.members} of 50 members
          {circle.owner ? (
            <>
              {" "}
              · run by{" "}
              <Link href={`/u/${circle.owner.handle}`} className="link">
                {circle.owner.display_name}
              </Link>
            </>
          ) : null}{" "}
          · started {formatDate(circle.created_at)}
          {circle.role === "owner" ? " · you run this circle" : ""}
        </p>
        <div className="mt-4 flex flex-wrap items-center gap-2">
          {circle.is_member ? (
            confirmLeave ? (
              <span className="flex flex-wrap items-center gap-2 text-sm">
                {circle.role === "owner"
                  ? "Leave? The longest-standing member will take over."
                  : "Leave this circle?"}
                <button type="button" className="btn btn-small btn-primary" onClick={leave} disabled={busy}>
                  {busy ? "Leaving…" : "Leave"}
                </button>
                <button type="button" className="btn btn-small" onClick={() => setConfirmLeave(false)} disabled={busy}>
                  Cancel
                </button>
              </span>
            ) : (
              <button type="button" className="btn btn-small" onClick={() => setConfirmLeave(true)}>
                Leave circle
              </button>
            )
          ) : (
            <button type="button" className="btn btn-small btn-primary" onClick={join} disabled={busy || full}>
              {full ? "Circle full" : busy ? "Joining…" : "Join circle"}
            </button>
          )}
        </div>
        <ErrorNote error={actionError} />
      </header>

      <section aria-labelledby="thread-title" className="mt-10">
        <h2 id="thread-title" className="font-serif text-2xl font-semibold">
          Conversation
        </h2>
        {circle.is_member ? (
          <CircleThread circle={circle} />
        ) : (
          <p className="panel mt-4 p-6 text-center text-muted">
            {user ? "Join the circle to read and post messages." : "Sign in and join the circle to read and post messages."}
          </p>
        )}
      </section>
    </div>
  );
}
