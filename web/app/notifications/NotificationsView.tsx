"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { announceNotificationsChanged, markNotificationsRead, notificationHref } from "@/lib/engage";
import { timeAgo } from "@/lib/social";
import { useLoad } from "@/lib/use-load";
import type { AppNotification } from "@/lib/types";

const ICONS: Record<string, string> = { daily: "☀️", reply: "💬", follow: "👋", circle: "📚", reward: "🎉" };

export function NotificationsView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Notifications</h1>
      <div className="mt-8">
        <RequireAuth message="Sign in to see replies, new followers and circle activity.">
          <Inbox />
        </RequireAuth>
      </div>
    </div>
  );
}

/**
 * The inbox. Opening it marks what it shows as read on the server, so the bell's badge
 * clears while you're looking at the list, but the rows that were new
 * keep their highlight and dot until you leave, so you can still see what's new.
 */
export function Inbox() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.notifications(50), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, setData } = useLoad(loader);
  const [actionError, setActionError] = useState<string | null>(null);
  // Ids marked read on the server while this list is open (their rows still show as new).
  const [seen, setSeen] = useState<ReadonlySet<string>>(() => new Set());
  const attempted = useRef(new Set<string>());

  const list = data?.notifications ?? [];
  const fresh = list.filter((n) => !n.read_at).map((n) => n.id);
  const freshKey = fresh.join(",");

  useEffect(() => {
    const ids = freshKey ? freshKey.split(",").filter((id) => !attempted.current.has(id)) : [];
    if (!ids.length) return;
    ids.forEach((id) => attempted.current.add(id));
    api
      .readNotifications(ids)
      .then(() => {
        setSeen((s) => new Set([...s, ...ids]));
        announceNotificationsChanged();
      })
      .catch(() => {
        // Leave them unread on the server: "Mark all as read" stays available.
      });
  }, [api, freshKey]);

  if (loading) return <Loading />;
  if (error) return <ErrorNote error={error} />;

  // Still unread on the server: marking failed, or the server has more than this page shows.
  const unreadOnServer = Math.max(0, (data?.unread ?? 0) - fresh.filter((id) => seen.has(id)).length);

  async function markRead(ids?: string[]) {
    const before = data;
    setData((d) => markNotificationsRead(d?.notifications ?? [], ids));
    setActionError(null);
    try {
      await api.readNotifications(ids);
      announceNotificationsChanged();
    } catch (err) {
      if (before) setData(() => before);
      setActionError(isApiError(err) ? err.message : "Couldn't mark as read.");
    }
  }

  if (!list.length) {
    return <p className="panel p-6 text-center text-muted">Nothing yet. Replies, follows and circle messages will show up here.</p>;
  }

  return (
    <>
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-muted" role="status">
          {fresh.length ? `${fresh.length} new` : "All caught up"}
        </p>
        {unreadOnServer ? (
          <button type="button" className="btn btn-small" onClick={() => markRead()}>
            Mark all as read
          </button>
        ) : null}
      </div>
      <ErrorNote error={actionError} />
      <ul className="mt-4 divide-y divide-line overflow-hidden rounded-xl border border-line bg-surface">
        {list.map((n) => (
          <NotificationRow key={n.id} n={n} onOpen={() => (!n.read_at && !seen.has(n.id) ? markRead([n.id]) : undefined)} />
        ))}
      </ul>
    </>
  );
}

function NotificationRow({ n, onOpen }: { n: AppNotification; onOpen: () => void }) {
  const unread = !n.read_at;
  return (
    <li className={unread ? "bg-accent-soft/60" : ""} data-unread={unread || undefined}>
      <Link href={notificationHref(n)} onClick={onOpen} className="flex gap-3 px-4 py-3 hover:bg-surface-2">
        <span aria-hidden="true" className="text-xl leading-6">
          {ICONS[n.kind] ?? "•"}
        </span>
        <span className="min-w-0 flex-1">
          <span className={`block break-words ${unread ? "font-semibold" : ""}`}>{n.text}</span>
          <span className="text-xs text-muted">
            <time dateTime={n.created_at}>{timeAgo(n.created_at)}</time>
            {unread ? <span className="sr-only"> · unread</span> : null}
          </span>
        </span>
        {unread ? <span aria-hidden="true" className="mt-2 size-2 shrink-0 rounded-full bg-accent" /> : null}
      </Link>
    </li>
  );
}
