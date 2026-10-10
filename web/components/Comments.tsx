"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { threadComments } from "@/lib/comments";
import { timeAgo } from "@/lib/social";
import { useLoad } from "@/lib/use-load";
import type { Comment, User } from "@/lib/types";
import { ErrorNote, Loading } from "./SignInPrompt";

const MAX = 1000;

/** Comments on a post: list, add, reply (one level), delete your own, report. */
export function Comments({ postId }: { postId: string }) {
  const { api, user, ready } = useAuth();
  const pathname = usePathname();
  const loader = useCallback(() => api.comments(postId, { limit: 50 }), [api, postId]);
  const { data, error, loading, setData } = useLoad(loader);
  const [more, setMore] = useState<{ busy: boolean; error: string | null }>({ busy: false, error: null });

  const add = (c: Comment) =>
    setData((prev) => ({ comments: [...(prev?.comments ?? []), c], next_cursor: prev?.next_cursor ?? null }));
  const remove = (id: string) =>
    setData((prev) => ({
      comments: (prev?.comments ?? []).filter((c) => c.id !== id && c.parent_id !== id),
      next_cursor: prev?.next_cursor ?? null,
    }));

  async function loadMore() {
    if (!data?.next_cursor) return;
    setMore({ busy: true, error: null });
    try {
      const page = await api.comments(postId, { cursor: data.next_cursor, limit: 50 });
      setData((prev) => {
        const have = prev?.comments ?? [];
        return {
          comments: [...have, ...page.comments.filter((c) => !have.some((h) => h.id === c.id))],
          next_cursor: page.next_cursor,
        };
      });
      setMore({ busy: false, error: null });
    } catch (err) {
      setMore({ busy: false, error: isApiError(err) ? err.message : "Couldn't load more comments." });
    }
  }

  const threads = threadComments(data?.comments ?? []);
  const count = data?.comments.length ?? 0;

  return (
    <section id="comments" aria-labelledby="comments-title" className="mx-auto mt-12 max-w-read scroll-mt-24">
      <h2 id="comments-title" className="font-serif text-2xl font-semibold">
        Comments{count ? <span className="text-muted"> ({count}{data?.next_cursor ? "+" : ""})</span> : null}
      </h2>

      {!ready ? null : user ? (
        <div className="mt-4">
          <CommentForm postId={postId} onAdded={add} label="Add a comment" />
        </div>
      ) : (
        <p className="mt-4 text-muted">
          <Link href={`/signin?next=${encodeURIComponent(`${pathname || `/ideas/${postId}`}#comments`)}`} className="link">
            Sign in
          </Link>{" "}
          to join the conversation.
        </p>
      )}

      {loading ? (
        <Loading label="Loading comments…" />
      ) : error ? (
        <ErrorNote error={error} />
      ) : threads.length === 0 ? (
        <p className="mt-6 text-muted">No comments yet.{user ? " Start the conversation." : ""}</p>
      ) : (
        <ul className="mt-6 space-y-5">
          {threads.map((t) => (
            <li key={t.comment.id}>
              <CommentItem comment={t.comment} user={user} postId={postId} onAdded={add} onRemoved={remove} canReply />
              {t.replies.length ? (
                <ul className="mt-3 space-y-3 border-l-2 border-line pl-4 sm:ml-4">
                  {t.replies.map((r) => (
                    <li key={r.id}>
                      <CommentItem comment={r} user={user} postId={postId} onAdded={add} onRemoved={remove} replyTo={t.comment.id} canReply />
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      <ErrorNote error={more.error} />
      {data?.next_cursor ? (
        <div className="mt-6 text-center">
          <button type="button" className="btn" onClick={loadMore} disabled={more.busy}>
            {more.busy ? "Loading…" : "Show more comments"}
          </button>
        </div>
      ) : null}
    </section>
  );
}

function CommentForm({
  postId,
  parentId,
  onAdded,
  onCancel,
  label,
  autoFocus,
}: {
  postId: string;
  parentId?: string;
  onAdded: (c: Comment) => void;
  onCancel?: () => void;
  label: string;
  autoFocus?: boolean;
}) {
  const { api } = useAuth();
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const id = `comment-${postId}-${parentId ?? "new"}`;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const text = body.trim();
    if (!text) return;
    setBusy(true);
    setError(null);
    try {
      const c = await api.addComment(postId, { body: text, parent_id: parentId ?? null });
      onAdded(c);
      setBody("");
      onCancel?.();
    } catch (err) {
      setError(
        isApiError(err) && err.status === 429
          ? "You've commented a lot in the last hour. Please try again later."
          : isApiError(err)
            ? err.message
            : "Couldn't post your comment.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit}>
      <label htmlFor={id} className={parentId ? "sr-only" : "label"}>
        {label}
      </label>
      <textarea
        id={id}
        className="field min-h-20"
        maxLength={MAX}
        value={body}
        autoFocus={autoFocus}
        placeholder={parentId ? "Write a reply…" : "What did this idea make you think of?"}
        onChange={(e) => setBody(e.target.value)}
      />
      <div className="mt-2 flex items-center justify-between gap-2">
        <span className="text-xs text-muted">
          {body.length}/{MAX}
        </span>
        <span className="flex gap-2">
          {onCancel ? (
            <button type="button" className="btn btn-small" onClick={onCancel}>
              Cancel
            </button>
          ) : null}
          <button type="submit" className="btn btn-small btn-primary" disabled={busy || !body.trim()}>
            {busy ? "Posting…" : parentId ? "Reply" : "Post comment"}
          </button>
        </span>
      </div>
      <ErrorNote error={error} />
    </form>
  );
}

function CommentItem({
  comment,
  user,
  postId,
  replyTo,
  canReply,
  onAdded,
  onRemoved,
}: {
  comment: Comment;
  user: User | null;
  postId: string;
  /** Top-level comment that replies attach to (replies are one level deep). */
  replyTo?: string;
  canReply?: boolean;
  onAdded: (c: Comment) => void;
  onRemoved: (id: string) => void;
}) {
  const { api } = useAuth();
  const [replying, setReplying] = useState(false);
  const [confirm, setConfirm] = useState<"delete" | "report" | null>(null);
  const [reported, setReported] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const mine = !!user && user.id === comment.author.id;
  const canDelete = mine || user?.role === "moderator";

  async function run(kind: "delete" | "report") {
    setBusy(true);
    setError(null);
    try {
      if (kind === "delete") {
        await api.deleteComment(comment.id);
        onRemoved(comment.id);
        return;
      }
      await api.reportComment(comment.id);
      setReported(true);
      setConfirm(null);
    } catch (err) {
      setError(isApiError(err) ? err.message : kind === "delete" ? "Couldn't delete the comment." : "Couldn't report the comment.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <article aria-label={`Comment by ${comment.author.display_name}`}>
      <p className="text-sm">
        <Link href={`/u/${comment.author.handle}`} className="font-semibold hover:underline">
          {comment.author.display_name}
        </Link>{" "}
        <span className="text-muted">
          @{comment.author.handle} ·{" "}
          <time dateTime={comment.created_at} title={new Date(comment.created_at).toLocaleString()}>
            {timeAgo(comment.created_at)}
          </time>
        </span>
      </p>
      <p className="mt-1 whitespace-pre-line break-words">{comment.body}</p>
      {user ? (
        <div className="mt-1 flex flex-wrap items-center gap-x-3 text-sm">
          {canReply ? (
            <button type="button" className="text-muted hover:text-fg hover:underline" onClick={() => setReplying((r) => !r)}>
              Reply
            </button>
          ) : null}
          {canDelete ? (
            <button type="button" className="text-muted hover:text-fg hover:underline" onClick={() => setConfirm("delete")}>
              Delete
            </button>
          ) : null}
          {!mine ? (
            reported ? (
              <span role="status" className="text-muted">
                Reported. Thanks for letting us know.
              </span>
            ) : (
              <button type="button" className="text-muted hover:text-fg hover:underline" onClick={() => setConfirm("report")}>
                Report
              </button>
            )
          ) : null}
        </div>
      ) : null}
      {confirm ? (
        <div role="alertdialog" aria-label={confirm === "delete" ? "Delete comment?" : "Report comment?"} className="mt-2 rounded-lg border border-line bg-surface-2 p-3 text-sm">
          <p>
            {confirm === "delete"
              ? "Delete this comment? Its replies go too. This can't be undone."
              : "Report this comment to the moderators as unkind, spam or off-topic?"}
          </p>
          <div className="mt-2 flex gap-2">
            <button type="button" className="btn btn-small btn-primary" disabled={busy} onClick={() => run(confirm)}>
              {busy ? "Please wait…" : confirm === "delete" ? "Delete" : "Report"}
            </button>
            <button type="button" className="btn btn-small" disabled={busy} onClick={() => setConfirm(null)}>
              Cancel
            </button>
          </div>
        </div>
      ) : null}
      <ErrorNote error={error} />
      {replying ? (
        <div className="mt-2">
          <CommentForm
            postId={postId}
            parentId={replyTo ?? comment.id}
            onAdded={onAdded}
            onCancel={() => setReplying(false)}
            label={`Reply to ${comment.author.display_name}`}
            autoFocus
          />
        </div>
      ) : null}
    </article>
  );
}
