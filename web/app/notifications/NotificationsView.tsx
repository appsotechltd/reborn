"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
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

export function Inbox() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.notifications(50), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, setData } = useLoad(loader);
  const [actionError, setActionError] = useState<string | null>(null);

  if (loading) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  const list = data?.notifications ?? [];

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
          {data?.unread ? `${data.unread} unread` : "All caught up"}
        </p>
        <button type="button" className="btn btn-small" disabled={!data?.unread} onClick={() => markRead()}>
          Mark all as read
        </button>
      </div>
      <ErrorNote error={actionError} />
      <ul className="mt-4 divide-y divide-line overflow-hidden rounded-xl border border-line bg-surface">
        {list.map((n) => (
          <NotificationRow key={n.id} n={n} onOpen={() => (!n.read_at ? markRead([n.id]) : undefined)} />
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
