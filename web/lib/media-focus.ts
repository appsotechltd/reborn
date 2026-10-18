/**
 * Listen mode, videos and AI replies read aloud never talk over each other: while Listen mode
 * plays, everything else on the page is paused (and feed videos don't start by themselves), and
 * when the reader starts a video or a reply, Listen mode pauses.
 */

let listening = false;
const videoListeners = new Set<() => void>();

/** Listen mode started or stopped playing. Starting pauses every video on the page. */
export function setListeningPlaying(on: boolean) {
  listening = on;
  if (!on || typeof document === "undefined") return;
  // Every <video> and <audio> on the page: explainers, illustrated videos' narration, AI replies read aloud.
  // Listen mode's own player isn't in the page.
  document.querySelectorAll<HTMLMediaElement>("video, audio").forEach((v) => {
    if (!v.paused) v.pause();
  });
}

/** True while Listen mode is playing: feed videos stay still. */
export function isListeningPlaying(): boolean {
  return listening;
}

/** The reader started a video (with sound): Listen mode pauses. */
export function videoStarted() {
  videoListeners.forEach((l) => l());
}

/** Called whenever the reader starts a video. Returns an unsubscribe function. */
export function onVideoStarted(listener: () => void): () => void {
  videoListeners.add(listener);
  return () => {
    videoListeners.delete(listener);
  };
}
