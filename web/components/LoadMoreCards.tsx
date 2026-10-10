"use client";

import { useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { Card } from "@/lib/types";
import { CardPreview } from "./CardPreview";

/** Appends further pages of GET /v1/feed?topics=… below server-rendered cards. */
export function LoadMoreCards({ topic, initialCursor }: { topic: string; initialCursor: string | null }) {
  const { api } = useAuth();
  const [cards, setCards] = useState<Card[]>([]);
  const [cursor, setCursor] = useState(initialCursor);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function more() {
    if (!cursor) return;
    setLoading(true);
    setError(null);
    try {
      // Anonymous on purpose: the cursor came from an anonymous server render.
      const page = await api.feed({ topics: topic, cursor, limit: 12 }, false);
      setCards((c) => [...c, ...page.cards.filter((n) => !c.some((o) => o.id === n.id))]);
      setCursor(page.next_cursor);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load more ideas.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      {cards.length ? (
        <ul className="mt-4 grid gap-4 sm:grid-cols-2" aria-label="More ideas">
          {cards.map((c) => (
            <CardPreview key={c.id} card={c} showTopic={false} />
          ))}
        </ul>
      ) : null}
      {error ? (
        <p role="alert" className="mt-4 text-bad">
          {error}
        </p>
      ) : null}
      {cursor ? (
        <div className="mt-6 text-center">
          <button type="button" className="btn" onClick={more} disabled={loading}>
            {loading ? "Loading…" : "Load more ideas"}
          </button>
        </div>
      ) : null}
    </>
  );
}
