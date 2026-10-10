"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatCount, REACTIONS, reactionInfo, totalReactions, withFavorite, withReaction } from "@/lib/social";
import type { Post, ReactionKind } from "@/lib/types";
import { EmbedButton } from "./EmbedButton";
import { GiftButton } from "./GiftButton";
import { ShareMenu } from "./ShareMenu";
import { useSignInRedirect } from "./SignInPrompt";

interface PostActionsProps {
  post: Post;
  /** Re-read the post (counts and the viewer's state) once signed-in state is known. */
  refresh?: boolean;
  /** Where the comment count links to. */
  commentsHref?: string;
}

/** Reactions, favourite, comments, share, embed and gift for one post, with optimistic updates. */
export function PostActions({ post: initial, refresh = false, commentsHref }: PostActionsProps) {
  const { ready, token, user, api } = useAuth();
  const toSignIn = useSignInRedirect();
  const [post, setPost] = useState<Post>(initial);
  const [error, setError] = useState<string | null>(null);
  const pending = useRef(0);

  useEffect(() => {
    if (!refresh || !ready) return;
    let cancelled = false;
    api
      .post(initial.id)
      .then((p) => {
        if (!cancelled && pending.current === 0) setPost(p);
      })
      .catch(() => {
        // Keep the server-rendered counts.
      });
    return () => {
      cancelled = true;
    };
  }, [refresh, ready, token, api, initial.id]);

  async function optimistic(next: Post, call: () => Promise<void>, failure: string) {
    const before = post;
    setPost(next);
    setError(null);
    pending.current++;
    try {
      await call();
    } catch (err) {
      setPost(before);
      setError(isApiError(err) ? err.message : failure);
    } finally {
      pending.current--;
    }
  }

  function react(kind: ReactionKind) {
    if (!user) return toSignIn();
    const next = post.viewer?.reaction === kind ? null : kind;
    optimistic(withReaction(post, next), () => api.setReaction(post.id, next), "Couldn't save your reaction.");
  }

  function favorite() {
    if (!user) return toSignIn();
    const on = !post.viewer?.favorited;
    optimistic(withFavorite(post, on), () => api.setFavorite(post.id, on), "Couldn't update your favourites.");
  }

  const favorited = !!user && !!post.viewer?.favorited;
  const comments = post.stats.comments;

  return (
    <div className="mx-auto mt-6 w-full max-w-read" data-testid="post-actions">
      <div className="flex flex-wrap items-center gap-1 border-t border-line pt-3">
        <ReactionControl post={post} signedIn={!!user} onReact={react} />
        <button
          type="button"
          className={`btn btn-small btn-ghost ${favorited ? "text-accent" : ""}`}
          aria-pressed={favorited}
          onClick={favorite}
        >
          <span aria-hidden="true">{favorited ? "♥" : "♡"}</span>
          <span className="sr-only">{favorited ? "Favourited" : "Favourite"}</span>
          <span aria-hidden="true">{formatCount(post.stats.favorites)}</span>
          <span className="sr-only">, {post.stats.favorites} favourites</span>
        </button>
        <Link href={commentsHref ?? `/ideas/${post.id}#comments`} className="btn btn-small btn-ghost">
          <span aria-hidden="true">💬</span> {formatCount(comments)}
          <span className="sr-only"> {comments === 1 ? "comment" : "comments"}</span>
        </Link>
        <ShareMenu
          postId={post.id}
          title={post.card.title}
          onShared={() => setPost((p) => ({ ...p, stats: { ...p.stats, shares: p.stats.shares + 1 } }))}
        />
        <EmbedButton postId={post.id} title={post.card.title} />
        <GiftButton postId={post.id} title={post.card.title} />
      </div>
      {error ? (
        <p role="alert" className="mt-2 text-sm text-bad">
          {error}
        </p>
      ) : null}
    </div>
  );
}

function ReactionControl({
  post,
  signedIn,
  onReact,
}: {
  post: Post;
  signedIn: boolean;
  onReact: (kind: ReactionKind) => void;
}) {
  const [open, setOpen] = useState(false);
  const wrap = useRef<HTMLDivElement>(null);
  const mine = signedIn ? (post.viewer?.reaction ?? null) : null;
  const total = totalReactions(post);
  const top = REACTIONS.filter((r) => (post.stats.reactions[r.kind] ?? 0) > 0)
    .sort((a, b) => (post.stats.reactions[b.kind] ?? 0) - (post.stats.reactions[a.kind] ?? 0))
    .slice(0, 3);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (wrap.current && !wrap.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const current = mine ? reactionInfo(mine) : null;

  return (
    <div ref={wrap} className="relative">
      <button
        type="button"
        className={`btn btn-small btn-ghost ${current ? "text-accent" : ""}`}
        aria-expanded={open}
        aria-haspopup="true"
        onClick={() => setOpen((o) => !o)}
      >
        <span aria-hidden="true">{current ? current.emoji : top.length ? top.map((r) => r.emoji).join("") : "👍"}</span>
        <span>{current ? current.label : "React"}</span>
        {total ? (
          <>
            <span aria-hidden="true" className="text-muted">
              {formatCount(total)}
            </span>
            <span className="sr-only">, {total} reactions</span>
          </>
        ) : null}
      </button>
      {open ? (
        <div
          role="group"
          aria-label="Reactions"
          className="absolute bottom-full left-0 z-20 mb-2 flex gap-1 rounded-full border border-line bg-surface p-1 shadow-lg"
        >
          {REACTIONS.map((r) => {
            const count = post.stats.reactions[r.kind] ?? 0;
            const active = mine === r.kind;
            return (
              <button
                key={r.kind}
                type="button"
                title={active ? `${r.label} (tap again to remove)` : r.label}
                aria-pressed={active}
                aria-label={`${r.label}, ${count}`}
                className={`flex min-h-11 min-w-11 flex-col items-center justify-center rounded-full px-2 text-xs hover:bg-surface-2 ${
                  active ? "bg-accent-soft font-semibold" : ""
                }`}
                onClick={() => {
                  setOpen(false);
                  onReact(r.kind);
                }}
              >
                <span aria-hidden="true" className="text-lg leading-none">
                  {r.emoji}
                </span>
                <span aria-hidden="true" className="mt-0.5 text-muted">
                  {formatCount(count)}
                </span>
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
