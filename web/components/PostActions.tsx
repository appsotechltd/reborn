"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatCount, REACTIONS, reactionInfo, totalReactions, withFavorite, withReaction } from "@/lib/social";
import type { Post, ReactionKind } from "@/lib/types";
import { EmbedButton } from "./EmbedButton";
import { GiftButton } from "./GiftButton";
import { Icon } from "./Icon";
import { ListenIconButton } from "./ListenButton";
import { ReportButton } from "./ReportButton";
import { ShareMenu } from "./ShareMenu";
import { StashButton } from "./StashButton";
import { useSignInRedirect } from "./SignInPrompt";

interface PostActionsProps {
  post: Post;
  /** Re-read the post (counts and the viewer's state) once signed-in state is known. */
  refresh?: boolean;
  /** Where the comment count links to. */
  commentsHref?: string;
  /** Spacing above the actions (default `mt-6`). */
  className?: string;
  /** In the phone feed: below md, no rule above and no Embed, so it fits under the card. */
  compact?: boolean;
  /** A Listen button for the post's card (feeds; the card's own page has its own). */
  listen?: boolean;
}

/**
 * The post's action bar, the same anatomy as the app's: favourite, one React button (its picker has
 * all five), comments, save to a collection and share, embed (web only) and Gift at the end. Counts
 * show once they are above zero. Optimistic updates throughout.
 */
export function PostActions({ post: initial, refresh = false, commentsHref, className = "mt-6", compact = false, listen = false }: PostActionsProps) {
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
  const mine = user ? (post.viewer?.reaction ?? null) : null;
  const comments = post.stats.comments;
  // A member's card: others can report it, and its writer can't gift their own.
  const author = post.card.author ?? null;
  const own = !!author && !!user && author.id === user.id;

  return (
    <div className={`mx-auto w-full max-w-read ${className}`} data-testid="post-actions">
      <div className={`-ml-2.5 flex flex-wrap items-center gap-0.5 border-t border-line pt-2 ${compact ? "max-md:border-0 max-md:pt-0.5" : ""}`}>
        <button
          type="button"
          className={`btn btn-small btn-ghost gap-1.5 px-2.5 ${favorited ? "text-react" : "text-muted hover:text-fg"}`}
          aria-pressed={favorited}
          onClick={favorite}
        >
          <Icon name={favorited ? "favorite" : "favoriteBorder"} />
          <span className="sr-only">{favorited ? "Favourited" : "Favourite"}</span>
          {post.stats.favorites > 0 ? <span aria-hidden="true">{formatCount(post.stats.favorites)}</span> : null}
          <span className="sr-only">, {post.stats.favorites} favourites</span>
        </button>
        <ReactButton post={post} mine={mine} onReact={react} />
        <Link
          href={commentsHref ?? `/ideas/${post.id}#comments`}
          className="btn btn-small btn-ghost gap-1.5 px-2.5 text-muted hover:text-fg"
        >
          <Icon name="comment" />
          {comments > 0 ? <span aria-hidden="true">{formatCount(comments)}</span> : null}
          <span className="sr-only">
            {comments} {comments === 1 ? "comment" : "comments"}
          </span>
        </Link>
        {/* Off the narrowest phones, so the row never wraps (as in the app). */}
        <span className="max-[359px]:hidden">
          <StashButton cardId={post.card.id} cardTitle={post.card.title} icon />
        </span>
        <ShareMenu
          postId={post.id}
          title={post.card.title}
          count={post.stats.shares || undefined}
          onShared={() => setPost((p) => ({ ...p, stats: { ...p.stats, shares: p.stats.shares + 1 } }))}
        />
        {/* The phone feed's preview has its own Listen button beside "Read the idea". */}
        {listen ? (
          <span className={compact ? "max-md:hidden" : undefined}>
            <ListenIconButton card={post.card} />
          </span>
        ) : null}
        {/* Embedding is a web thing for people with sites; it stays off the phone feed to keep one row. */}
        <span className={compact ? "max-md:hidden" : undefined}>
          <EmbedButton postId={post.id} title={post.card.title} />
        </span>
        {author && !own ? <ReportButton postId={post.id} title={post.card.title} /> : null}
        {own ? null : (
          <span className="ml-auto">
            <GiftButton postId={post.id} title={post.card.title} count={post.stats.gifts} author={author?.display_name} />
          </span>
        )}
      </div>
      {error ? (
        <p role="alert" className="mt-2 text-sm text-bad">
          {error}
        </p>
      ) : null}
    </div>
  );
}

/**
 * One React button, as in the app: your reaction (or the add-reaction face) and the total. It opens
 * the five reactions above it, each with its count once it has one; picking yours again takes it back.
 */
function ReactButton({
  post,
  mine,
  onReact,
}: {
  post: Post;
  mine: ReactionKind | null;
  onReact: (kind: ReactionKind) => void;
}) {
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const total = totalReactions(post);
  const current = mine ? reactionInfo(mine) : null;

  useEffect(() => {
    if (!open) return;
    box.current?.querySelector<HTMLButtonElement>("[aria-pressed=true], button")?.focus();
    const away = (e: PointerEvent) => {
      if (!box.current?.contains(e.target as Node)) setOpen(false);
    };
    const key = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      setOpen(false);
      trigger.current?.focus();
    };
    document.addEventListener("pointerdown", away);
    document.addEventListener("keydown", key);
    return () => {
      document.removeEventListener("pointerdown", away);
      document.removeEventListener("keydown", key);
    };
  }, [open]);

  function pick(kind: ReactionKind) {
    setOpen(false);
    onReact(kind);
    trigger.current?.focus();
  }

  return (
    <div ref={box} className="relative">
      <button
        ref={trigger}
        type="button"
        aria-expanded={open}
        aria-label={`${current ? `Your reaction: ${current.label}` : "React"}, ${total} ${total === 1 ? "reaction" : "reactions"}`}
        data-testid="post-react"
        onClick={() => setOpen((o) => !o)}
        className={`btn btn-small btn-ghost gap-1.5 px-2.5 ${current ? "font-semibold text-react" : "text-muted hover:text-fg"}`}
      >
        {current ? (
          <span aria-hidden="true" className="text-[1.125rem] leading-none">
            {current.emoji}
          </span>
        ) : (
          <Icon name="addReaction" />
        )}
        {total > 0 ? <span aria-hidden="true">{formatCount(total)}</span> : null}
      </button>
      {open ? (
        <div
          role="group"
          aria-label="Reactions"
          className="absolute bottom-full left-0 z-20 mb-2 flex gap-0.5 rounded-full border border-line bg-surface p-1 shadow-[var(--nav-shadow)]"
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
                onClick={() => pick(r.kind)}
                className={`inline-flex h-11 min-w-11 items-center justify-center gap-1 rounded-full px-2 text-[0.8125rem] font-semibold hover:bg-surface-2 ${
                  active ? "bg-accent-soft text-react" : "text-muted"
                }`}
              >
                <span aria-hidden="true" className="text-[1.375rem] leading-none">
                  {r.emoji}
                </span>
                {count > 0 ? <span aria-hidden="true">{formatCount(count)}</span> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
