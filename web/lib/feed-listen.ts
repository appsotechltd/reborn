import { useSyncExternalStore } from "react";

/*
 * The home feed's "Listen to this feed", offered by the header on phones (as in the app's top bar)
 * while the timeline is on screen and has something to play. The timeline registers it here.
 */

let action: (() => void) | null = null;
const listeners = new Set<() => void>();

export function setFeedListen(next: (() => void) | null) {
  if (action === next) return;
  action = next;
  listeners.forEach((l) => l());
}

function subscribe(l: () => void) {
  listeners.add(l);
  return () => {
    listeners.delete(l);
  };
}

export function useFeedListen(): (() => void) | null {
  return useSyncExternalStore(
    subscribe,
    () => action,
    () => null,
  );
}
