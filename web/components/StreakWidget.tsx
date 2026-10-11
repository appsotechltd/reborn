"use client";

import Link from "next/link";
import { useCallback } from "react";
import { useAuth } from "@/lib/auth";
import { weekday } from "@/lib/engage";
import { useLoad } from "@/lib/use-load";
import type { Streak } from "@/lib/types";
import { Icon } from "./Icon";

/** Current streak, today's ideas against the daily goal, and the last 7 days. Signed-in only. */
export function StreakWidget() {
  const { ready, token, api } = useAuth();
  const loader = useCallback(() => api.streak(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data } = useLoad(ready && token ? loader : null);
  if (!data) return null;
  return <StreakCard streak={data} />;
}

export function StreakCard({ streak }: { streak: Streak }) {
  return (
    <>
      <PhoneStreakCard streak={streak} />
      <WideStreakCard streak={streak} />
    </>
  );
}

/** The app's streak card, on phones: flame and count, today against the goal, the week's dots. */
function PhoneStreakCard({ streak }: { streak: Streak }) {
  const goal = Math.max(1, streak.goal);
  const pct = Math.min(100, Math.round((streak.today / goal) * 100));
  const days = streak.current === 1 ? "1-day streak" : `${streak.current}-day streak`;
  return (
    <section aria-label="Your reading streak" className="panel mb-2 flex shrink-0 items-center gap-4 p-4 md:hidden">
      <p className="flex flex-col items-center">
        <Icon name="fire" className={`size-8 ${streak.current > 0 ? "text-react" : "text-muted"}`} />
        <span className="font-serif text-xl font-semibold leading-tight">{streak.current}</span>
        <span className="sr-only">{days}</span>
      </p>
      <div className="min-w-0 flex-1">
        <p aria-hidden="true" className="text-sm font-semibold">
          {days}
        </p>
        <p className="mt-0.5 text-[0.8125rem] text-muted">
          {streak.goal_met ? "Goal met: " : ""}
          {streak.today} of {streak.goal} ideas today
        </p>
        <div
          role="progressbar"
          aria-label="Today's goal"
          aria-valuemin={0}
          aria-valuemax={goal}
          aria-valuenow={Math.min(streak.today, goal)}
          className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-surface-2"
        >
          <div className="h-full rounded-full bg-accent" style={{ width: `${pct}%` }} />
        </div>
        <ol className="mt-2.5 flex justify-between" aria-label="Last 7 days">
          {(streak.last_days ?? []).map((d) => {
            const met = d.ideas >= goal;
            return (
              <li key={d.day} className="flex flex-col items-center gap-0.5 text-[0.6875rem] font-medium">
                <span
                  aria-hidden="true"
                  className={`size-[1.125rem] rounded-full ${met ? "bg-accent" : d.ideas > 0 ? "bg-accent-soft" : "bg-surface-2"}`}
                />
                <span aria-hidden="true">{weekday(d.day).slice(0, 1)}</span>
                <span className="sr-only">
                  {weekday(d.day)}: {d.ideas} {d.ideas === 1 ? "idea" : "ideas"}
                </span>
              </li>
            );
          })}
        </ol>
      </div>
    </section>
  );
}

function WideStreakCard({ streak }: { streak: Streak }) {
  const goal = Math.max(1, streak.goal);
  const pct = Math.min(100, Math.round((streak.today / goal) * 100));
  return (
    <section aria-label="Your reading streak" className="panel mx-auto mb-6 max-w-3xl max-md:hidden flex flex-wrap items-center gap-x-6 gap-y-3 p-4 sm:px-6">
      <p className="flex items-baseline gap-2">
        <span aria-hidden="true" className="text-2xl">🔥</span>
        <span className="text-2xl font-semibold">{streak.current}</span>
        <span className="text-sm text-muted">
          day{streak.current === 1 ? "" : "s"} streak
          {streak.longest > streak.current ? ` · best ${streak.longest}` : ""}
        </span>
      </p>
      <div className="min-w-40 flex-1">
        <p className="text-sm">
          <strong>{streak.today}</strong> of {goal} ideas today{streak.goal_met ? " · goal met ✓" : ""}
        </p>
        <div
          role="progressbar"
          aria-label="Today's goal"
          aria-valuemin={0}
          aria-valuemax={goal}
          aria-valuenow={Math.min(streak.today, goal)}
          className="mt-1 h-2 overflow-hidden rounded-full bg-surface-2"
        >
          <div className={`h-full rounded-full ${streak.goal_met ? "bg-ok" : "bg-accent"}`} style={{ width: `${pct}%` }} />
        </div>
      </div>
      <ol className="flex gap-1.5" aria-label="Last 7 days">
        {(streak.last_days ?? []).map((d) => {
          const met = d.ideas >= goal;
          return (
            <li key={d.day} className="flex flex-col items-center gap-0.5 text-[0.6875rem] text-muted">
              <span
                className={`grid size-6 place-items-center rounded-full text-[0.6875rem] font-semibold ${
                  met ? "bg-ok text-bg" : d.ideas > 0 ? "bg-accent-soft text-fg" : "bg-surface-2"
                }`}
                title={`${d.day}: ${d.ideas} ${d.ideas === 1 ? "idea" : "ideas"}`}
              >
                {d.ideas || ""}
              </span>
              <span aria-hidden="true">{weekday(d.day).slice(0, 2)}</span>
              <span className="sr-only">
                {weekday(d.day)}: {d.ideas} {d.ideas === 1 ? "idea" : "ideas"}
              </span>
            </li>
          );
        })}
      </ol>
      <Link href="/settings#goal" className="inline-flex items-center text-xs text-muted hover:underline pointer-coarse:min-h-11">
        Change goal
      </Link>
    </section>
  );
}
