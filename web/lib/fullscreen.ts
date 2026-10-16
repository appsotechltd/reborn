/** Browser full-screen calls, including the prefixed ones Safari still uses. */
type FsElement = HTMLElement & { webkitRequestFullscreen?: () => Promise<void> | void };
type FsVideo = HTMLVideoElement & { webkitEnterFullscreen?: () => void; webkitDisplayingFullscreen?: boolean };
type FsDocument = Document & { webkitFullscreenElement?: Element | null; webkitExitFullscreen?: () => Promise<void> | void };

/** The element on full screen now, if any. */
export function fullscreenElement(): Element | null {
  const d = document as FsDocument;
  return d.fullscreenElement ?? d.webkitFullscreenElement ?? null;
}

/**
 * Puts `el` on full screen. Must run inside the reader's tap. Returns false when the browser can't
 * (an iPhone can only show a <video> on full screen, which `video` covers).
 */
export function enterFullscreen(el: HTMLElement, video?: HTMLVideoElement): boolean {
  const e = el as FsElement;
  try {
    if (typeof e.requestFullscreen === "function") {
      Promise.resolve(e.requestFullscreen()).catch(() => {});
      return true;
    }
    if (typeof e.webkitRequestFullscreen === "function") {
      Promise.resolve(e.webkitRequestFullscreen()).catch(() => {});
      return true;
    }
    const v = video as FsVideo | undefined;
    if (v && typeof v.webkitEnterFullscreen === "function") {
      v.webkitEnterFullscreen();
      return true;
    }
  } catch {
    // Refused: fall through.
  }
  return false;
}

export function exitFullscreen() {
  const d = document as FsDocument;
  try {
    if (typeof d.exitFullscreen === "function") Promise.resolve(d.exitFullscreen()).catch(() => {});
    else d.webkitExitFullscreen?.();
  } catch {
    // Already left.
  }
}

/** Calls `onChange` whenever the page enters or leaves full screen (including an iPhone's video player). */
export function onFullscreenChange(onChange: () => void, video?: HTMLVideoElement | null): () => void {
  const events = ["fullscreenchange", "webkitfullscreenchange"];
  events.forEach((n) => document.addEventListener(n, onChange));
  video?.addEventListener("webkitbeginfullscreen", onChange);
  video?.addEventListener("webkitendfullscreen", onChange);
  return () => {
    events.forEach((n) => document.removeEventListener(n, onChange));
    video?.removeEventListener("webkitbeginfullscreen", onChange);
    video?.removeEventListener("webkitendfullscreen", onChange);
  };
}

/** Whether `video` (or `el`) is on full screen now. */
export function isFullscreen(el: Element | null, video?: HTMLVideoElement | null): boolean {
  const f = fullscreenElement();
  if (f && (f === el || (el && el.contains(f)) || f === video)) return true;
  return !!(video as FsVideo | null | undefined)?.webkitDisplayingFullscreen;
}
