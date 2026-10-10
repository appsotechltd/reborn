"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { PremiumBadge } from "@/components/PremiumBadge";
import { ErrorNote, Loading, useSignInRedirect } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { planPrice, premiumSummary } from "@/lib/engage";
import { useLoad } from "@/lib/use-load";

const PERKS = [
  { title: "10x the AI guide", text: "Ask the guide ten times as many questions every hour." },
  { title: "Support the library", text: "Help keep every idea card free to read, credited and checked." },
  { title: "Same account everywhere", text: "Premium follows you to the Reborn apps on iPhone and Android." },
];

const STORE_NAMES: Record<string, string> = { apple: "the App Store", google: "Google Play" };

export function PremiumView({ welcome = false }: { welcome?: boolean }) {
  const { ready, token, user, api, setUser } = useAuth();
  const toSignIn = useSignInRedirect();
  const loader = useCallback(() => api.premium(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad(ready ? loader : null);
  const [busy, setBusy] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  // After checkout, refresh the profile so the Premium badge appears everywhere.
  useEffect(() => {
    if (!welcome || !token) return;
    let cancelled = false;
    api
      .me()
      .then((u) => {
        if (!cancelled) setUser(u);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [welcome, token, api, setUser]);

  async function subscribe(plan: string) {
    if (!user) return toSignIn();
    setBusy(plan);
    setActionError(null);
    try {
      const { url } = await api.premiumCheckout(plan);
      window.location.assign(url);
    } catch (err) {
      setActionError(
        isApiError(err) && err.code === "premium_unavailable"
          ? "Premium on the web is coming soon."
          : isApiError(err)
            ? err.message
            : "Couldn't start the payment. Please try again.",
      );
      setBusy(null);
    }
  }

  async function manage() {
    setBusy("portal");
    setActionError(null);
    try {
      const { url } = await api.premiumPortal();
      window.location.assign(url);
    } catch (err) {
      setActionError(
        isApiError(err) && err.status === 404
          ? "There's no web subscription on this account. If you subscribed in the app, manage it in your phone's store settings."
          : isApiError(err)
            ? err.message
            : "Couldn't open billing. Please try again.",
      );
      setBusy(null);
    }
  }

  const sub = data?.subscription ?? null;
  const stripe = data?.providers.stripe ?? false;

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mx-auto max-w-read text-center">
        <p className="eyebrow">Reborn Premium</p>
        <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight text-balance">Go further with every idea</h1>
        <p className="mt-3 text-lg text-muted">Everything in Reborn stays free to read. Premium adds more room to think.</p>
      </header>

      {welcome ? (
        <div role="status" className="mx-auto mt-8 max-w-read rounded-xl border border-ok bg-apply px-5 py-4 text-apply-fg">
          <p className="font-semibold">Welcome to Premium, and thank you!</p>
          <p className="mt-1 text-sm">
            It can take a moment for your payment to be confirmed. Your guide limit goes up as soon as it is.
          </p>
        </div>
      ) : null}

      <ul className="mt-10 grid gap-4 sm:grid-cols-3">
        {PERKS.map((p) => (
          <li key={p.title} className="panel p-5">
            <h2 className="font-semibold">{p.title}</h2>
            <p className="mt-1 text-sm text-muted">{p.text}</p>
          </li>
        ))}
      </ul>

      {!ready || loading ? (
        <Loading />
      ) : error || !data ? (
        <ErrorNote error={error ?? "Couldn't load Premium."} />
      ) : (
        <section aria-labelledby="plan-title" className="mt-10">
          <h2 id="plan-title" className="sr-only">
            Your plan
          </h2>
          {user ? (
            <div className="panel mx-auto max-w-read p-5 text-center" data-testid="premium-status">
              {data.premium ? <PremiumBadge /> : null}
              <p className="mt-2">{premiumSummary(data)}</p>
              {data.premium && sub?.provider === "stripe" ? (
                <button type="button" className="btn mt-4" onClick={manage} disabled={busy !== null}>
                  {busy === "portal" ? "Opening…" : "Manage billing"}
                </button>
              ) : data.premium && sub && STORE_NAMES[sub.provider] ? (
                <p className="mt-2 text-sm text-muted">Manage your subscription in {STORE_NAMES[sub.provider]}.</p>
              ) : null}
            </div>
          ) : null}

          {!data.premium ? (
            <>
              <ul className="mx-auto mt-6 grid max-w-read gap-4 sm:grid-cols-2">
                {data.plans.map((p) => (
                  <li key={p.id} className="panel flex flex-col p-5 text-center">
                    <h3 className="font-serif text-xl font-semibold">{p.name}</h3>
                    <p className="mt-1 text-2xl font-semibold">{planPrice(p)}</p>
                    {p.id === "yearly" ? <p className="text-sm text-ok">Save a third compared with monthly</p> : null}
                    <button
                      type="button"
                      className="btn btn-primary mt-4"
                      disabled={!stripe || busy !== null}
                      onClick={() => subscribe(p.id)}
                    >
                      {busy === p.id ? "Opening checkout…" : user ? "Subscribe" : "Sign in to subscribe"}
                    </button>
                  </li>
                ))}
              </ul>
              {!stripe ? (
                <p role="status" className="mx-auto mt-4 max-w-read rounded-lg border border-line bg-surface-2 px-3 py-2 text-center text-sm">
                  Premium on the web is coming soon.
                </p>
              ) : (
                <p className="mt-4 text-center text-sm text-muted">
                  Secure payment with Stripe. Cancel any time from Manage billing.
                </p>
              )}
            </>
          ) : null}
          <ErrorNote error={actionError} />
          <p className="mt-8 text-center text-sm text-muted">
            Prefer to share?{" "}
            <Link href="/invite" className="link">
              Invite friends
            </Link>{" "}
            and you both get free Premium days.
          </p>
        </section>
      )}
    </div>
  );
}
