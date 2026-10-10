"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { ErrorNote } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { excerpt } from "@/lib/content";
import { mergeMessages } from "@/lib/engage";
import { timeAgo } from "@/lib/social";
import type { Card, Circle, CircleMessage } from "@/lib/types";

export const POLL_MS = 10_000;
const PAGE = 50;
const MAX = 2000;

/** A circle's message thread: polls every 10s while the page is open and visible. */
export function CircleThread({ circle }: { circle: Circle }) {
  const { api, user } = useAuth();
  const [messages, setMessages] = useState<CircleMessage[] | null>(null);
  const [hasOlder, setHasOlder] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [olderBusy, setOlderBusy] = useState(false);
  const [cards, setCards] = useState<Card[] | null>(null);
  const loadedOnce = useRef(false);

  // The book's ideas, to attach to messages and to show attached ones.
  useEffect(() => {
    let cancelled = false;
    api
      .source(circle.source.id)
      .then((r) => {
        if (!cancelled) setCards(r.cards);
      })
      .catch(() => {
        if (!cancelled) setCards([]);
      });
    return () => {
      cancelled = true;
    };
  }, [api, circle.source.id]);

  const refresh = useCallback(async () => {
    try {
      const r = await api.circleMessages(circle.id, { limit: PAGE });
      if (!loadedOnce.current) {
        loadedOnce.current = true;
        setHasOlder(r.messages.length === PAGE);
      }
      // The latest page is authoritative for its time range, so deletions show up too.
      const from = r.messages.length < PAGE ? "" : r.messages[0].created_at;
      setMessages((m) => mergeMessages(m ?? [], r.messages, from));
      setError(null);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load messages.");
    }
  }, [api, circle.id]);

  useEffect(() => {
    const tick = () => {
      if (document.visibilityState !== "hidden") refresh();
    };
    tick();
    const timer = window.setInterval(tick, POLL_MS);
    const onVisible = () => {
      if (document.visibilityState === "visible") refresh();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [refresh]);

  async function older() {
    if (!messages?.length) return;
    setOlderBusy(true);
    try {
      const r = await api.circleMessages(circle.id, { before: messages[0].created_at, limit: PAGE });
      setMessages((m) => mergeMessages(m ?? [], r.messages));
      setHasOlder(r.messages.length === PAGE);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load earlier messages.");
    } finally {
      setOlderBusy(false);
    }
  }

  async function remove(m: CircleMessage) {
    setMessages((list) => (list ?? []).filter((x) => x.id !== m.id));
    try {
      await api.deleteCircleMessage(circle.id, m.id);
    } catch (err) {
      setMessages((list) => mergeMessages(list ?? [], [m]));
      setError(isApiError(err) ? err.message : "Couldn't delete the message.");
    }
  }

  const byId = new Map((cards ?? []).map((c) => [c.id, c]));
  const canModerate = circle.role === "owner" || user?.role === "moderator";

  return (
    <div className="mt-4">
      {messages === null && !error ? (
        <p role="status" className="py-6 text-center text-muted">
          Loading messages…
        </p>
      ) : null}
      {hasOlder ? (
        <div className="mb-4 text-center">
          <button type="button" className="btn btn-small" onClick={older} disabled={olderBusy}>
            {olderBusy ? "Loading…" : "Show earlier messages"}
          </button>
        </div>
      ) : null}
      {messages?.length === 0 ? <p className="text-muted">No messages yet. Say hello and share what you&apos;re reading.</p> : null}
      <ol className="space-y-4" aria-label="Messages" aria-live="polite">
        {(messages ?? []).map((m) => (
          <li key={m.id}>
            <Message
              m={m}
              card={m.post_id ? byId.get(m.post_id) : undefined}
              canDelete={!!user && (m.author.id === user.id || canModerate)}
              onDelete={() => remove(m)}
            />
          </li>
        ))}
      </ol>
      <ErrorNote error={error} />
      <Composer
        circleId={circle.id}
        cards={cards ?? []}
        onPosted={(m) => setMessages((list) => mergeMessages(list ?? [], [m]))}
      />
    </div>
  );
}

function Message({
  m,
  card,
  canDelete,
  onDelete,
}: {
  m: CircleMessage;
  card?: Card;
  canDelete: boolean;
  onDelete: () => void;
}) {
  const [confirm, setConfirm] = useState(false);
  return (
    <article aria-label={`Message from ${m.author.display_name}`}>
      <p className="text-sm">
        <Link href={`/u/${m.author.handle}`} className="font-semibold hover:underline">
          {m.author.display_name}
        </Link>{" "}
        <span className="text-muted">
          <time dateTime={m.created_at} title={new Date(m.created_at).toLocaleString()}>
            {timeAgo(m.created_at)}
          </time>
        </span>
        {canDelete ? (
          confirm ? (
            <span className="ml-2">
              <button type="button" className="text-bad hover:underline" onClick={onDelete}>
                Delete
              </button>{" "}
              <button type="button" className="text-muted hover:underline" onClick={() => setConfirm(false)}>
                Cancel
              </button>
            </span>
          ) : (
            <button type="button" className="ml-2 text-muted hover:text-fg hover:underline" onClick={() => setConfirm(true)}>
              Delete
            </button>
          )
        ) : null}
      </p>
      <p className="mt-1 whitespace-pre-line break-words">{m.body}</p>
      {m.post_id ? (
        <Link
          href={`/ideas/${m.post_id}`}
          className="mt-2 block rounded-xl border border-line bg-surface p-3 hover:border-accent"
          data-testid="attached-idea"
        >
          <span className="block text-xs font-semibold uppercase tracking-wider text-muted">Idea</span>
          <span className="block font-serif font-semibold">{card?.title ?? "Open the idea"}</span>
          {card ? <span className="mt-1 block text-sm text-muted">{excerpt(card.body, 120)}</span> : null}
        </Link>
      ) : null}
    </article>
  );
}

export function Composer({
  circleId,
  cards,
  onPosted,
}: {
  circleId: string;
  cards: Card[];
  onPosted: (m: CircleMessage) => void;
}) {
  const { api } = useAuth();
  const [body, setBody] = useState("");
  const [postId, setPostId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const area = useRef<HTMLTextAreaElement>(null);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const text = body.trim();
    if (!text) return;
    setBusy(true);
    setError(null);
    try {
      const m = await api.postCircleMessage(circleId, { body: text, ...(postId ? { post_id: postId } : {}) });
      onPosted(m);
      setBody("");
      setPostId("");
      area.current?.focus();
    } catch (err) {
      setError(
        isApiError(err) && err.status === 429
          ? "You've sent a lot of messages. Please wait a little."
          : isApiError(err)
            ? err.message
            : "Couldn't send your message.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={send} className="panel mt-6 space-y-3 p-4">
      <label htmlFor="circle-message" className="sr-only">
        Your message
      </label>
      <textarea
        id="circle-message"
        ref={area}
        className="field min-h-20"
        maxLength={MAX}
        placeholder="Share a thought about the book…"
        value={body}
        onChange={(e) => setBody(e.target.value)}
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0 flex-1">
          <label htmlFor="circle-attach" className="sr-only">
            Attach an idea from this book
          </label>
          <select id="circle-attach" className="field min-h-10 py-1 text-sm" value={postId} onChange={(e) => setPostId(e.target.value)}>
            <option value="">Attach an idea (optional)</option>
            {cards.map((c) => (
              <option key={c.id} value={c.id}>
                {c.title}
              </option>
            ))}
          </select>
        </div>
        <button type="submit" className="btn btn-primary" disabled={busy || !body.trim()}>
          {busy ? "Sending…" : "Send"}
        </button>
      </div>
      <ErrorNote error={error} />
    </form>
  );
}
