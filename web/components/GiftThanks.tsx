"use client";

import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "@/lib/auth";
import { formatMoney } from "@/lib/social";
import type { Gift } from "@/lib/types";

const POLL_MS = 2000;
const MAX_POLLS = 15;

/**
 * After Stripe Checkout returns to /ideas/{id}?gift={giftId}, polls the gift
 * briefly and thanks the signed-in giver once the payment is confirmed.
 */
export function GiftThanks() {
  const params = useSearchParams();
  const giftId = params.get("gift");
  const { token, api } = useAuth();
  const [state, setState] = useState<{ id: string; gift: Gift | null; done: boolean } | null>(null);

  useEffect(() => {
    if (!giftId || !token) return;
    let cancelled = false;
    let polls = 0;
    let timer: number | undefined;
    const tick = async () => {
      polls++;
      let gift: Gift | null = null;
      try {
        gift = await api.gift(giftId);
      } catch {
        gift = null;
      }
      if (cancelled) return;
      const settled = gift?.status === "paid" || gift?.status === "refunded";
      const done = settled || polls >= MAX_POLLS;
      setState({ id: giftId, gift, done });
      if (!done) timer = window.setTimeout(tick, POLL_MS);
    };
    tick();
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [giftId, token, api]);

  if (!giftId || !token) return null;
  const current = state?.id === giftId ? state : null;
  const gift = current?.gift;

  if (gift?.status === "paid") {
    return (
      <div role="status" className="mx-auto mb-8 max-w-read rounded-xl border border-ok bg-apply px-5 py-4 text-apply-fg">
        <p className="font-semibold">Thank you for your gift!</p>
        <p className="mt-1 text-sm">
          Your {formatMoney(gift.amount_cents, gift.currency)} gift supports Reborn and helps keep the library free for
          everyone.
        </p>
      </div>
    );
  }
  if (current?.done) {
    return (
      <div role="status" className="mx-auto mb-8 max-w-read rounded-xl border border-line bg-surface px-5 py-4 text-sm">
        We haven&apos;t had confirmation of your gift yet. If you completed the payment, it will show up shortly. Thank
        you!
      </div>
    );
  }
  return (
    <p role="status" className="mx-auto mb-8 max-w-read text-sm text-muted">
      Confirming your gift…
    </p>
  );
}
