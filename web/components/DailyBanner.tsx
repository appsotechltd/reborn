"use client";

import Link from "next/link";
import { useCallback } from "react";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import { Icon } from "./Icon";

/**
 * "Today's idea" at the top of the phone feed, as in the app: a card with the day's idea that
 * opens it. Phones only (below md); renders nothing until (or unless) the idea has loaded.
 */
export function DailyBanner() {
  const { ready, api } = useAuth();
  const loader = useCallback(() => api.daily(), [api]);
  const { data } = useLoad(ready ? loader : null);
  if (!data?.card) return null;
  return (
    <Link
      href={`/ideas/${data.card.id}`}
      className="panel mb-2 flex shrink-0 items-center gap-3 py-3 pl-4 pr-3 hover:bg-surface-2 md:hidden"
      data-testid="daily-banner"
    >
      <Icon name="sun" className="size-6 text-accent-text" />
      <span className="min-w-0 flex-1">
        <span className="eyebrow block text-[0.6875rem]">Today&apos;s idea</span>
        <span className="mt-1 line-clamp-2 font-serif text-lg font-semibold leading-snug">{data.card.title}</span>
      </span>
      <Icon name="chevronRight" className="size-6 text-muted" />
    </Link>
  );
}
