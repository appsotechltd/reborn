/**
 * Listen mode and explainer videos never talk over each other: while Listen mode plays, videos
 * on the page are paused (and feed videos don't start by themselves), and when the reader starts
 * a video, Listen mode pauses.
 */

let listening = false;
const videoListeners = new Set<() => void>();

/** Listen mode started or stopped playing. Starting pauses every video on the page. */
export function setListeningPlaying(on: boolean) {
  listening = on;
  if (!on || typeof document === "undefined") return;
  // Illustrated videos play their narration in an <audio data-video-audio>.
  document.querySelectorAll<HTMLMediaElement>("video, audio[data-video-audio]").forEach((v) => {
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
