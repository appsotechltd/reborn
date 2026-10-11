"use client";

import { useHydrated } from "@/lib/auth";
import { useListen } from "@/lib/listen";
import type { Card } from "@/lib/types";
import { Icon } from "./Icon";

/**
 * Plays this one card in Listen mode: its recording when it has one, else the browser's own voice
 * reading the same text. Pressing it again pauses or resumes. Hidden when neither can play here.
 */
export function ListenButton({ card }: { card: Card }) {
  const hydrated = useHydrated();
  const { player, state } = useListen();
  if (!hydrated || !player || !player.canPlay(card)) return null;

  const current = state.active && state.items[state.index]?.id === card.id && state.phase !== "finished";
  const playing = current && state.playing;

  function press() {
    if (!player) return;
    if (current) player.toggle();
    else player.start({ items: [{ id: card.id, card }], single: true });
  }

  return (
    <button type="button" className="btn btn-small" onClick={press} aria-pressed={playing}>
      <Icon name={playing ? "pause" : "headphones"} className="size-4" />
      {playing ? "Pause" : current ? "Resume" : "Listen"}
    </button>
  );
}
