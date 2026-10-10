"use client";

import { useCallback, useEffect, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { FollowKind, FollowState } from "@/lib/types";
import { useSignInRedirect } from "./SignInPrompt";

interface FollowButtonProps {
  kind: FollowKind;
  /** User id, source id or author name. */
  target: string;
  /** What is being followed, for screen readers ("Meditations"). */
  label: string;
  /** Follower count rendered on the server (anonymous, so is_following is false). */
  initial?: FollowState | null;
  /** Reads the signed-in viewer's follow state once auth is known. Memoise it. */
  load?: () => Promise<FollowState>;
  /** Hide the follower count. */
  hideCount?: boolean;
  onChange?: (state: FollowState) => void;
}

/** Follow / Following toggle with an optimistic follower count. Signed-out visitors go to sign in. */
export function FollowButton({ kind, target, label, initial, load, hideCount, onChange }: FollowButtonProps) {
  const { ready, token, user, api } = useAuth();
  const toSignIn = useSignInRedirect();
  const [state, setState] = useState<FollowState>(initial ?? { followers: 0, is_following: false });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!ready || !token || !load) return;
    let cancelled = false;
    load()
      .then((s) => {
        if (!cancelled) setState(s);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [ready, token, load]);

  async function toggle() {
    if (!user) return toSignIn();
    const before = state;
    const on = !state.is_following;
    setState({ followers: Math.max(0, state.followers + (on ? 1 : -1)), is_following: on });
    setBusy(true);
    setError(null);
    try {
      const next = await api.setFollow(kind, target, on);
      setState(next);
      onChange?.(next);
    } catch (err) {
      setState(before);
      setError(isApiError(err) ? err.message : "Couldn't update. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  const following = !!user && state.is_following;

  return (
    <span className="inline-flex flex-wrap items-center gap-3">
      <button
        type="button"
        className={`btn btn-small ${following ? "" : "btn-primary"}`}
        aria-pressed={following}
        onClick={toggle}
        disabled={busy}
      >
        {following ? "Following ✓" : "Follow"}
        <span className="sr-only"> {label}</span>
      </button>
      {!hideCount ? (
        <span className="text-sm text-muted">
          {state.followers} {state.followers === 1 ? "follower" : "followers"}
        </span>
      ) : null}
      {error ? (
        <span role="alert" className="text-sm text-bad">
          {error}
        </span>
      ) : null}
    </span>
  );
}

/** Follow a book or other source (for server-rendered source pages). */
export function SourceFollowButton({ id, title, initial }: { id: string; title: string; initial?: FollowState | null }) {
  const { api } = useAuth();
  const load = useCallback(
    () => api.source(id).then((r) => r.follow ?? { followers: 0, is_following: false }),
    [api, id],
  );
  return <FollowButton kind="source" target={id} label={title} initial={initial} load={load} />;
}

/** Follow an author (for server-rendered author pages). */
export function AuthorFollowButton({ name, initial }: { name: string; initial?: FollowState | null }) {
  const { api } = useAuth();
  const load = useCallback(
    () => api.author(name).then((a) => ({ followers: a.followers, is_following: a.is_following })),
    [api, name],
  );
  return <FollowButton kind="author" target={name} label={name} initial={initial} load={load} />;
}
