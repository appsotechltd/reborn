"use client";

import { createContext, useContext, useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { currentToken, useAuth } from "./auth";
import { ListenPlayer, type ListenState } from "./listen-player";
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
  sleep: null,
  single: false,
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
