"use client";

import { useEffect } from "react";
import { useAuth } from "@/lib/auth";

/** Records that a signed-in reader opened a card (used by the feed). */
export function ViewTracker({ cardId }: { cardId: string }) {
  const { token, api } = useAuth();
  useEffect(() => {
    if (!token) return;
    api.recordView(cardId).catch(() => {
      // Best effort; never interrupt reading.
    });
  }, [api, token, cardId]);
  return null;
}
