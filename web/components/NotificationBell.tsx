"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "@/lib/auth";
import { NOTIFICATIONS_CHANGED } from "@/lib/engage";
import { Icon } from "./Icon";

const POLL_MS = 60_000;

/** Header bell with the unread notification count. Hidden when signed out. */
export function NotificationBell() {
  const { ready, token, api } = useAuth();
  const pathname = usePathname();
  const [count, setCount] = useState<{ token: string; unread: number } | null>(null);

  useEffect(() => {
    if (!ready || !token) return;
    let cancelled = false;
    const load = () => {
      if (document.visibilityState === "hidden") return;
      api
        .notifications(1)
        .then((r) => {
          if (!cancelled) setCount({ token, unread: r.unread });
        })
        .catch(() => {});
    };
    load();
    const timer = window.setInterval(load, POLL_MS);
    window.addEventListener(NOTIFICATIONS_CHANGED, load);
    window.addEventListener("focus", load);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      window.removeEventListener(NOTIFICATIONS_CHANGED, load);
      window.removeEventListener("focus", load);
    };
  }, [ready, token, api, pathname]);

  if (!ready || !token) return null;
  const unread = count?.token === token ? count.unread : 0;
  return (
    <Link
      href="/notifications"
      className="btn btn-small btn-ghost relative size-11 p-0 text-muted hover:text-fg"
      aria-current={pathname === "/notifications" ? "page" : undefined}
    >
      <Icon name="bell" className="size-6" />
      <span className="sr-only">Notifications{unread ? `, ${unread} unread` : ""}</span>
      {unread ? (
        <span
          aria-hidden="true"
          className="absolute right-0.5 top-0.5 grid min-w-5 place-items-center rounded-full bg-oxblood px-1 text-xs font-bold text-oxblood-fg"
        >
          {unread > 99 ? "99+" : unread}
        </span>
      ) : null}
    </Link>
  );
}
