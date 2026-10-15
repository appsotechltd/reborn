"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { useHydrated } from "@/lib/auth";
import { useListen, useListenFollow, useListenMove } from "@/lib/listen";
import { itemsFromCards } from "@/lib/listen-player";
import type { Card } from "@/lib/types";
import { CardList } from "./CardPreview";
import { Icon } from "./Icon";

export type CardsFilter = "all" | "videos";

/** Video cards are the ones with an explainer. */
export function videoCards(cards: Card[]): Card[] {
  return cards.filter((c) => !!c.explainer);
}

/**
 * Every card of a book or an author, with an All / Videos switch (hidden when there are no videos)
 * and "Listen to this book/author", which plays the cards shown, in order, in Listen mode.
 * Server-rendered with All selected, so every card is in the page's HTML. While a session is on,
 * opening the page moves it to the cards shown, unless it is already this page's (All or Videos);
 * when the audio moves on to another card, that card's page opens.
 */
export function CardsBrowser({
  cards,
  queue,
  listenLabel,
  showTopic,
  context,
}: {
  cards: Card[];
  /** Names this list for Listen mode, e.g. "source:meditations". */
  queue: string;
  /** "Listen to this book", "Listen to this author". */
  listenLabel: string;
  showTopic?: boolean;
  /** Ends the heading: "12 ideas from this book", "3 videos by Epictetus". */
  context: string;
}) {
  const [filter, setFilter] = useState<CardsFilter>("all");
  const videos = videoCards(cards);
  const shown = filter === "videos" && videos.length ? videos : cards;
  const current = filter === "videos" && videos.length ? "videos" : "all";
  const { state: listen } = useListen();
  const ours = !!listen.queue?.startsWith(`${queue}|`);
  useListenFollow(ours ? null : { items: itemsFromCards(shown), queue: `${queue}|${current}` });
  const router = useRouter();
  useListenMove((item) => router.push(`/ideas/${encodeURIComponent(item.card.id)}`));

  return (
    <section aria-labelledby="cards-title">
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-3">
        <h2 id="cards-title" className="font-serif text-2xl font-semibold">
          {shown.length} {current === "videos" ? (shown.length === 1 ? "video" : "videos") : shown.length === 1 ? "idea" : "ideas"}{" "}
          {context}
        </h2>
        <ListenListButton cards={shown} queue={`${queue}|${current}`} label={listenLabel} />
      </div>
      {videos.length ? (
        <div role="group" aria-label="Show" className="mt-4 inline-flex rounded-full border border-line p-1">
          {(
            [
              ["all", "All", cards.length],
              ["videos", "Videos", videos.length],
            ] as const
          ).map(([id, label, count]) => {
            const on = current === id;
            return (
              <button
                key={id}
                type="button"
                aria-pressed={on}
                onClick={() => setFilter(id)}
                className={`inline-flex min-h-9 items-center gap-1.5 rounded-full px-4 text-sm pointer-coarse:min-h-11 ${
                  on ? "bg-chip-on font-semibold text-chip-on-fg" : "text-muted hover:text-fg"
                }`}
              >
                {id === "videos" ? <Icon name="play" className="size-4" /> : null}
                {label}{" "}
                <span className={on ? undefined : "text-muted"}>({count})</span>
              </button>
            );
          })}
        </div>
      ) : null}
      <div className="mt-4">
        <CardList cards={shown} showTopic={showTopic} />
      </div>
    </section>
  );
}

/**
 * Plays a fixed list of cards in Listen mode, from the first. While that list is the session it
 * pauses and resumes it instead. Hidden until hydrated, and when none of the cards can play here.
 */
export function ListenListButton({ cards, queue, label }: { cards: Card[]; queue: string; label: string }) {
  const hydrated = useHydrated();
  const { player, state } = useListen();
  if (!hydrated || !player || !cards.some((c) => player.canPlay(c))) return null;

  const current = state.active && state.queue === queue && state.phase !== "finished";
  const playing = current && state.playing;

  function press() {
    if (!player) return;
    if (current) player.toggle();
    else player.playCards(cards, { queue });
  }

  return (
    <button type="button" className="btn btn-small" onClick={press} aria-pressed={playing}>
      <Icon name={playing ? "pause" : "headphones"} className="size-4" />
      {playing ? "Pause" : current ? "Resume" : label}
    </button>
  );
}
