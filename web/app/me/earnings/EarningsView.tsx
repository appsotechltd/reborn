"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatMoney } from "@/lib/social";
import { useLoad } from "@/lib/use-load";
import type { EarningsResponse, MyPlanResponse, WriterSubscription } from "@/lib/types";

function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

export function EarningsView() {
  return (
    <div className="mx-auto max-w-read">
      <p>
        <Link href="/me/cards" className="link text-sm">
          ← My cards
        </Link>
      </p>
      <h1 className="mt-4 font-serif text-4xl font-semibold tracking-tight">Earnings</h1>
      <p className="mt-2 text-muted">Gifts on your cards and subscriptions to you.</p>
      <div className="mt-8">
        <RequireAuth message="Sign in to see your earnings.">
          <Earnings />
          <PlanEditor />
          <MySubscriptions />
        </RequireAuth>
      </div>
    </div>
  );
}

function Earnings() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.earnings(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad<EarningsResponse>(loader);
  if (loading) return <Loading />;
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load your earnings."} />;
  const e = data.earnings;
  const money = (cents: number, currency = e.currency) => formatMoney(cents, currency || "usd");
  const stats: [string, string][] = [
    ["Total", money(e.total_cents)],
    ["This month", money(e.this_month_cents)],
    ["Gifts", String(e.gifts)],
    ["Subscribers", String(e.subscribers)],
  ];
  return (
    <section aria-labelledby="earnings-title">
      <h2 id="earnings-title" className="sr-only">
        Your earnings
      </h2>
      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {stats.map(([label, value]) => (
          <div key={label} className="panel p-4">
            <dt className="text-sm text-muted">{label}</dt>
            <dd className="mt-1 text-2xl font-semibold">{value}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-3 text-sm text-muted">
        Reborn keeps {data.commission_percent}% after the payment fee. Payouts start once writer payouts are set up.
      </p>
      <h3 className="mt-8 font-serif text-xl font-semibold">Recent</h3>
      {e.recent?.length ? (
        <ul className="mt-3 divide-y divide-line border-y border-line">
          {e.recent.map((r, i) => (
            <li key={`${r.paid_at}-${i}`} className="flex items-start justify-between gap-4 py-3">
              <div className="min-w-0">
                <p className="font-medium">
                  {r.kind === "subscription" ? "Subscription" : "Gift"}
                  {r.from ? (
                    <>
                      {" "}
                      from{" "}
                      <Link href={`/u/${r.from.handle}`} className="link">
                        {r.from.display_name}
                      </Link>
                    </>
                  ) : null}
                </p>
                <p className="truncate text-sm text-muted">
                  {r.kind === "gift" && r.post_id ? (
                    <>
                      on{" "}
                      <Link href={`/ideas/${encodeURIComponent(r.post_id)}`} className="hover:underline">
                        {r.post_title || "your card"}
                      </Link>{" "}
                      ·{" "}
                    </>
                  ) : null}
                  {shortDate(r.paid_at)}
                </p>
              </div>
              <p className="shrink-0 text-right">
                <span className="font-semibold">{money(r.author_cents, r.currency)}</span>
                <span className="block text-xs text-muted">of {money(r.amount_cents, r.currency)}</span>
              </p>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-2 text-muted">Nothing yet. Gifts and subscriptions show up here.</p>
      )}
    </section>
  );
}

function PlanEditor() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.myPlan(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad<MyPlanResponse>(loader);
  if (loading) return <Loading />;
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load your subscription settings."} />;
  return <PlanForm data={data} />;
}

function PlanForm({ data }: { data: MyPlanResponse }) {
  const { api } = useAuth();
  const [enabled, setEnabled] = useState(data.plan?.enabled ?? false);
  const [tier, setTier] = useState(data.plan?.tier ?? data.tiers[1]?.id ?? data.tiers[0]?.id ?? "");
  const [pitch, setPitch] = useState(data.plan?.pitch ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await api.setMyPlan({ tier, enabled, pitch: pitch.trim() });
      setSaved(true);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't save your subscription settings.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={save} className="panel mt-12 space-y-4 p-5" aria-labelledby="plan-title">
      <h2 id="plan-title" className="font-serif text-2xl font-semibold">
        Subscriptions
      </h2>
      <p className="text-sm text-muted">
        Readers pay monthly to see your subscriber-only cards (and your followers-only ones).
        {data.plan ? ` ${data.plan.subscribers} ${data.plan.subscribers === 1 ? "subscriber" : "subscribers"} now.` : ""}
      </p>
      <label className="flex cursor-pointer items-center gap-3">
        <input type="checkbox" className="size-4" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
        <span className="font-semibold">Offer subscriptions</span>
      </label>
      <fieldset disabled={!enabled}>
        <legend className="label">Price</legend>
        <div className="flex flex-wrap gap-2">
          {data.tiers.map((t) => (
            <label
              key={t.id}
              className={`flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2 ${tier === t.id ? "border-accent bg-accent-soft" : "border-line"} ${enabled ? "" : "opacity-60"}`}
            >
              <input type="radio" name="tier" value={t.id} checked={tier === t.id} onChange={() => setTier(t.id)} className="size-4" />
              {formatMoney(t.amount_cents, t.currency)} a month
            </label>
          ))}
        </div>
      </fieldset>
      <div>
        <label htmlFor="plan-pitch" className="label">
          What subscribers get <span className="font-normal text-muted">(optional)</span>
        </label>
        <textarea
          id="plan-pitch"
          className="field min-h-20 resize-y"
          maxLength={300}
          value={pitch}
          onChange={(e) => setPitch(e.target.value)}
          aria-describedby="plan-pitch-hint"
        />
        <p id="plan-pitch-hint" className="hint">
          Shown on your page. {pitch.length}/300
        </p>
      </div>
      <ErrorNote error={error} />
      <div className="flex items-center gap-3">
        <button type="submit" className="btn btn-primary" disabled={busy || !tier}>
          {busy ? "Saving…" : "Save"}
        </button>
        {saved ? (
          <span role="status" className="text-sm font-semibold text-ok">
            Saved ✓
          </span>
        ) : null}
      </div>
    </form>
  );
}

function MySubscriptions() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.mySubscriptions().then((r) => r.subscriptions), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, setData } = useLoad<WriterSubscription[]>(loader);
  const [busy, setBusy] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  async function cancel(s: WriterSubscription) {
    if (!window.confirm(`Stop renewing your subscription to ${s.writer.display_name}? You keep it until it runs out.`)) return;
    setBusy(s.writer.handle);
    setActionError(null);
    try {
      const updated = await api.cancelSubscription(s.writer.handle);
      setData((list) => (list ?? []).map((o) => (o.writer.id === s.writer.id ? updated : o)));
    } catch (err) {
      setActionError(isApiError(err) ? err.message : "Couldn't cancel the renewal.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <section aria-labelledby="subs-title" className="mt-12">
      <h2 id="subs-title" className="font-serif text-2xl font-semibold">
        My subscriptions
      </h2>
      {loading ? (
        <Loading />
      ) : error ? (
        <ErrorNote error={error} />
      ) : !data?.length ? (
        <p className="mt-2 text-muted">You don&apos;t subscribe to any writers.</p>
      ) : (
        <ul className="mt-3 divide-y divide-line border-y border-line">
          {data.map((s) => (
            <li key={s.writer.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
              <div className="min-w-0">
                <Link href={`/u/${s.writer.handle}`} className="font-semibold hover:underline">
                  {s.writer.display_name}
                </Link>
                <p className="text-sm text-muted">
                  {!s.active ? `Ended ${shortDate(s.expires_at)}` : s.renews ? `Renews ${shortDate(s.expires_at)}` : `Until ${shortDate(s.expires_at)}`}
                </p>
              </div>
              {s.active && s.renews ? (
                <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => cancel(s)}>
                  Cancel renewal<span className="sr-only"> for {s.writer.display_name}</span>
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      <ErrorNote error={actionError} />
    </section>
  );
}
