"use client";

import { createContext, useContext, useEffect, useEffectEvent, useState, useSyncExternalStore, type ReactNode } from "react";
import { currentToken, useAuth } from "./auth";
import { ListenPlayer, type FollowTarget, type ListenItem, type ListenState } from "./listen-player";
import type { Card } from "./types";
import { onVideoStarted, setListeningPlaying } from "./media-focus";

const ListenContext = createContext<ListenPlayer | null>(null);

/**
 * The app-wide Listen mode player. Mounted once in the root layout, so a session keeps playing
 * while the reader moves between pages.
 */
export function ListenProvider({ children }: { children: ReactNode }) {
  const { api } = useAuth();
  // Seen and read are recorded only for a signed-in reader (read when the card ends, so a sign-out mid-session counts).
  const [player] = useState(() => new ListenPlayer({ api, signedIn: () => !!currentToken() }));

  // Listen mode and videos take turns: playing pauses videos, starting a video pauses this.
  useEffect(() => {
    let was = false;
    const unsubscribe = player.subscribe(() => {
      const now = player.getState().playing;
      if (now !== was) setListeningPlaying(now);
      was = now;
    });
    const off = onVideoStarted(() => player.pause());
    return () => {
      unsubscribe();
      off();
      setListeningPlaying(false);
    };
  }, [player]);

  return <ListenContext.Provider value={player}>{children}</ListenContext.Provider>;
}

const SERVER_STATE: ListenState = {
  active: false,
  items: [],
  index: 0,
  playing: false,
  phase: "idle",
  voice: "recording",
  position: 0,
  duration: 0,
  speed: 1,
  music: false,
  sleep: null,
  single: false,
  queue: null,
  loadingMore: false,
  error: null,
  session: 0,
};

const noop = () => () => {};

/** The player and its state. Outside a ListenProvider (embeds, tests) the player is null. */
export function useListen(): { player: ListenPlayer | null; state: ListenState } {
  const player = useContext(ListenContext);
  const state = useSyncExternalStore(
    player?.subscribe ?? noop,
    player ? player.getState : () => SERVER_STATE,
    () => SERVER_STATE,
  );
  return { player, state };
}

/**
 * Keeps Listen mode on this page's audio: while a session is on, opening the page (or moving to
 * another item on it) switches the session to `target`, from the item on screen. Pages without
 * audio of their own don't call this, so the session carries on there. null: nothing yet.
 */
export function useListenFollow(target: FollowTarget | null) {
  const player = useContext(ListenContext);
  const key = target ? `${target.queue}#${target.index == null ? "" : (target.items[target.index]?.id ?? "")}` : null;
  const follow = useEffectEvent(() => {
    if (target) player?.follow(target);
  });
  useEffect(() => {
    if (key) follow();
  }, [player, key]);
}

/**
 * The other way round: when the audio moves on to another card within the session (the next one,
 * or one picked in the player), `onMove` shows it on this page (opens its card, or scrolls or turns
 * to it). Starting a session opens nothing.
 */
export function useListenMove(onMove: (item: ListenItem) => void) {
  const player = useContext(ListenContext);
  const move = useEffectEvent(onMove);
  useEffect(() => {
    if (!player) return;
    let before = player.getState();
    return player.subscribe(() => {
      const now = player.getState();
      const was = before;
      before = now;
      const item = now.active ? now.items[now.index] : undefined;
      if (!item || now.session !== was.session || item.id === was.items[was.index]?.id) return;
      move(item);
    });
  }, [player]);
}

/** As useListenFollow, for a card's own page (see ListenPlayer.followCard). */
export function useListenFollowCard(card: Card) {
  const player = useContext(ListenContext);
  const follow = useEffectEvent(() => player?.followCard(card));
  useEffect(() => {
    follow();
  }, [player, card.id]);
}
