"use client";

import Link from "next/link";
import { useCallback } from "react";
import { DailyChart } from "@/components/DailyChart";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { useAuth } from "@/lib/auth";
import { formatMoney } from "@/lib/social";
import { useLoad } from "@/lib/use-load";
import type { AdminStats } from "@/lib/types";

export function AdminView() {
  return (
    <div>
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-muted">How Reborn is doing. Figures refresh every minute.</p>
      <div className="mt-8">
        <RequireAuth>
          <ModeratorOnly />
        </RequireAuth>
      </div>
    </div>
  );
}

function ModeratorOnly() {
  const { user } = useAuth();
  if (user?.role !== "moderator") {
    return (
      <div className="panel p-6 text-center">
        <h2 className="font-serif text-2xl font-semibold">Moderators only</h2>
        <p className="mt-2 text-muted">Your account doesn&apos;t have access to the dashboard.</p>
      </div>
    );
  }
  return <Dashboard />;
}

const pct = (v: number) => `${Math.round(v * 100)}%`;

function Tile({ label, value, hint }: { label: string; value: string | number; hint?: string }) {
  return (
    <div className="panel p-4">
      <dt className="text-sm text-muted">{label}</dt>
      <dd className="mt-1 text-2xl font-semibold tabular-nums">{value}</dd>
      {hint ? <dd className="text-xs text-muted">{hint}</dd> : null}
    </div>
  );
}

function Dashboard() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.adminStats(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad<AdminStats>(loader);
  if (loading) return <Loading />;
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load the dashboard."} />;
  const { users, retention, engagement, revenue, moderation, content } = data;
  const gifts = revenue.gifts_30d ?? [];
  const subs = revenue.subscriptions ?? [];
  const giftTotals = Object.entries(
    gifts.reduce<Record<string, number>>((acc, g) => ({ ...acc, [g.currency]: (acc[g.currency] ?? 0) + g.amount_cents }), {}),
  );

  return (
    <div className="space-y-12">
      <section aria-labelledby="users-title">
        <h2 id="users-title" className="font-serif text-2xl font-semibold">People</h2>
        <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Tile label="Members" value={users.total} hint={`+${users.new_7d} this week, +${users.new_30d} in 30 days`} />
          <Tile label="Daily active" value={users.dau} />
          <Tile label="Weekly active" value={users.wau} />
          <Tile label="Monthly active" value={users.mau} />
          <Tile label="Premium" value={users.premium} />
          <Tile label="Day-1 retention" value={pct(retention.d1)} hint={`Cohort of ${retention.cohort}`} />
          <Tile label="Day-7 retention" value={pct(retention.d7)} hint={`Cohort of ${retention.cohort}`} />
          <Tile label="Library" value={content.posts} hint={`ideas from ${content.sources} sources`} />
        </dl>
      </section>

      <section aria-labelledby="daily-title">
        <h2 id="daily-title" className="font-serif text-2xl font-semibold">Last 30 days</h2>
        <div className="panel mt-4 p-4">
          {data.daily?.length ? <DailyChart days={data.daily} /> : <p className="text-muted">No activity yet.</p>}
        </div>
      </section>

      <section aria-labelledby="engagement-title">
        <h2 id="engagement-title" className="font-serif text-2xl font-semibold">Engagement this week</h2>
        <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-5">
          <Tile label="Ideas read" value={engagement.ideas_read_7d} />
          <Tile label="Reactions" value={engagement.reactions_7d} />
          <Tile label="Comments" value={engagement.comments_7d} />
          <Tile label="Favourites" value={engagement.favorites_7d} />
          <Tile label="Shares" value={engagement.shares_7d} />
        </dl>
      </section>

      <div className="grid gap-10 md:grid-cols-2">
        <section aria-labelledby="revenue-title">
          <h2 id="revenue-title" className="font-serif text-2xl font-semibold">Revenue</h2>
          <h3 className="mt-4 font-semibold">Gifts, last 30 days</h3>
          {gifts.length ? (
            <>
              <p className="mt-1 text-2xl font-semibold">{giftTotals.map(([c, cents]) => formatMoney(cents, c)).join(" + ")}</p>
              <ul className="mt-2 text-sm text-muted">
                {gifts.map((g) => (
                  <li key={`${g.provider}-${g.currency}`}>
                    <span className="capitalize">{g.provider}</span>: {g.count} {g.count === 1 ? "gift" : "gifts"},{" "}
                    {formatMoney(g.amount_cents, g.currency)}
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <p className="mt-1 text-muted">No gifts yet.</p>
          )}
          <h3 className="mt-6 font-semibold">Active subscriptions</h3>
          {subs.length ? (
            <ul className="mt-1 text-sm">
              {subs.map((s) => (
                <li key={s.provider}>
                  <span className="capitalize">{s.provider}</span>: {s.count}
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-1 text-muted">None yet.</p>
          )}
        </section>

        <section aria-labelledby="moderation-title">
          <h2 id="moderation-title" className="font-serif text-2xl font-semibold">Moderation</h2>
          <ul className="mt-4 space-y-3">
            <li>
              <Link href="/moderation" className="panel flex items-center justify-between p-4 hover:border-accent">
                <span>Contributions waiting</span>
                <span className="text-xl font-semibold">{moderation.pending_contributions}</span>
              </Link>
            </li>
            <li>
              <Link href="/moderation#reported-title" className="panel flex items-center justify-between p-4 hover:border-accent">
                <span>Reported comments</span>
                <span className="text-xl font-semibold">{moderation.reported_comments}</span>
              </Link>
            </li>
          </ul>
        </section>
      </div>

      <section aria-labelledby="top-title">
        <h2 id="top-title" className="font-serif text-2xl font-semibold">Top posts this week</h2>
        {data.top_posts?.length ? (
          <ol className="mt-4 divide-y divide-line border-y border-line">
            {data.top_posts.map((p, i) => (
              <li key={p.id} className="flex items-baseline justify-between gap-3 py-3">
                <span className="min-w-0">
                  <span className="mr-2 text-muted">{i + 1}.</span>
                  <Link href={`/ideas/${p.id}`} className="hover:underline">{p.title}</Link>
                </span>
                <span className="shrink-0 text-sm text-muted">score {p.score}</span>
              </li>
            ))}
          </ol>
        ) : (
          <p className="mt-4 text-muted">No activity this week yet.</p>
        )}
      </section>
    </div>
  );
}
