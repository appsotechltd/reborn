"use client";

import { useRouter } from "next/navigation";
import { useHydrated } from "@/lib/auth";
import { useListen, useListenFollowCard, useListenMove } from "@/lib/listen";
import type { Card } from "@/lib/types";
import { Icon } from "./Icon";

/**
 * Plays this one card in Listen mode: its recording when it has one, else the browser's own voice
 * reading the same text. Pressing it again pauses or resumes. Hidden when neither can play here.
 * It sits on the card's page, so while a session is on, opening the page switches it to this card,
 * and when the audio moves on to another card, that card's page opens in place of this one.
 */
export function ListenButton({ card }: { card: Card }) {
  const hydrated = useHydrated();
  const router = useRouter();
  const { player, state } = useListen();
  useListenFollowCard(card);
  useListenMove((item) => {
    if (item.card.id !== card.id) router.replace(`/ideas/${encodeURIComponent(item.card.id)}`);
  });
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

/**
 * The feed's one-tap Listen for a post's card, an icon beside the post's actions: plays the card,
 * or pauses and resumes it while it's the one playing. Hidden when it can't play here.
 */
export function ListenIconButton({ card }: { card: Card }) {
  const hydrated = useHydrated();
  const { player, state } = useListen();
  if (!hydrated || !player || !player.canPlay(card)) return null;

  const current = state.active && state.items[state.index]?.card.id === card.id && state.phase !== "finished";
  const playing = current && state.playing;

  function press() {
    if (!player) return;
    if (current) player.toggle();
    else player.start({ items: [{ id: card.id, card }], single: true });
  }

  return (
    <button
      type="button"
      className="btn btn-small btn-ghost px-2.5 text-muted hover:text-fg"
      onClick={press}
      aria-pressed={playing}
      aria-label={playing ? "Pause this idea" : current ? "Resume this idea" : "Listen to this idea"}
      title={playing ? "Pause this idea" : "Listen to this idea"}
    >
      <Icon name={playing ? "pause" : "headphones"} />
    </button>
  );
}

/**
 * The phone feed preview's outlined Listen pill, beside "Read the idea" (as in the app): plays the
 * card, or pauses and resumes it while it's the one playing. Hidden when it can't play here.
 */
export function ListenPill({ card }: { card: Card }) {
  const hydrated = useHydrated();
  const { player, state } = useListen();
  if (!hydrated || !player || !player.canPlay(card)) return null;

  const current = state.active && state.items[state.index]?.card.id === card.id && state.phase !== "finished";
  const playing = current && state.playing;

  function press() {
    if (!player) return;
    if (current) player.toggle();
    else player.start({ items: [{ id: card.id, card }], single: true });
  }

  return (
    <button
      type="button"
      className="btn h-[2.875rem] shrink-0 gap-1.5 px-4"
      onClick={press}
      aria-pressed={playing}
      aria-label={playing ? "Pause this idea" : current ? "Resume this idea" : "Listen to this idea"}
    >
      <Icon name={playing ? "pause" : "headphones"} className="size-[1.125rem]" />
      {playing ? "Pause" : current ? "Resume" : "Listen"}
    </button>
  );
}
