"use client";

import { useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatCount, formatMoney } from "@/lib/social";
import type { GiftTiersResponse } from "@/lib/types";
import { Icon } from "./Icon";
import { Modal } from "./Modal";
import { useSignInRedirect } from "./SignInPrompt";

/** Gift dialog: pick a tier and pay with Stripe Checkout. Gifts support Reborn. */
export function GiftButton({ postId, title, count = 0 }: { postId: string; title: string; count?: number }) {
  const { user, api } = useAuth();
  const toSignIn = useSignInRedirect();
  const [open, setOpen] = useState(false);
  const [tiers, setTiers] = useState<GiftTiersResponse | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const titleId = `gift-${postId}-title`;

  async function show() {
    if (!user) return toSignIn();
    setOpen(true);
    setError(null);
    if (tiers) return;
    try {
      setTiers(await api.giftTiers());
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load the gift options.");
    }
  }

  async function checkout(tier: string) {
    setBusy(tier);
    setError(null);
    try {
      const res = await api.giftCheckout(postId, tier);
      window.location.assign(res.url);
    } catch (err) {
      setError(
        isApiError(err) && err.code === "gifts_unavailable"
          ? "Gifts are coming soon."
          : isApiError(err)
            ? err.message
            : "Couldn't start the payment. Please try again.",
      );
      setBusy(null);
    }
  }

  const enabled = tiers?.providers.stripe ?? false;

  return (
    <>
      <button type="button" className="btn btn-small btn-ghost gap-1.5 px-2.5 text-accent-text" aria-haspopup="dialog" onClick={show}>
        <Icon name="gift" />
        Gift
        {count > 0 ? <span> · {formatCount(count)}</span> : null}
        {!user ? <span className="sr-only"> (sign in to send a gift)</span> : null}
      </button>
      <Modal open={open} onClose={() => setOpen(false)} titleId={titleId}>
        <h2 id={titleId} className="font-serif text-xl font-semibold">
          Send a gift to Reborn
        </h2>
        <p className="mt-1 text-sm text-muted">
          Enjoyed “{title}”? A gift supports Reborn, the small team that writes, checks and credits these cards, and
          keeps the library free to read. Gifts are not passed on to the book&apos;s author or publisher.
        </p>
        {tiers === null && !error ? (
          <p role="status" className="mt-4 text-muted">
            Loading…
          </p>
        ) : null}
        {tiers ? (
          <>
            <ul className="mt-4 grid gap-2 sm:grid-cols-3">
              {tiers.tiers.map((t) => (
                <li key={t.id}>
                  <button
                    type="button"
                    className="btn w-full flex-col gap-0 py-3"
                    disabled={!enabled || busy !== null}
                    onClick={() => checkout(t.id)}
                  >
                    <span className="font-semibold">{t.name}</span>
                    <span className="text-sm text-muted">
                      {busy === t.id ? "Opening checkout…" : formatMoney(t.amount_cents, t.currency)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
            {!enabled ? (
              <p role="status" className="mt-3 rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm">
                Gifts are coming soon.
              </p>
            ) : (
              <p className="hint mt-3">You&apos;ll pay securely with Stripe and come straight back here.</p>
            )}
          </>
        ) : null}
        {error ? (
          <p role="alert" className="mt-3 text-sm text-bad">
            {error}
          </p>
        ) : null}
        <div className="mt-5 text-right">
          <button type="button" className="btn" onClick={() => setOpen(false)}>
            Close
          </button>
        </div>
      </Modal>
    </>
  );
}
