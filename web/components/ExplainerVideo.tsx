"use client";

import { useEffect, useRef, useState } from "react";
import { mediaUrl } from "@/lib/config";
import { enterFullscreen, isFullscreen, onFullscreenChange } from "@/lib/fullscreen";
import { useMediaQuery } from "@/lib/use-media-query";
import { isListeningPlaying, videoStarted } from "@/lib/media-focus";
import type { Card } from "@/lib/types";
import { Icon } from "./Icon";

/** After the reader presses play, how long to wait for playback before offering the fallback. */
export const PLAY_TIMEOUT_MS = 10_000;

/** Tablets and laptops play the landscape cut (when there is one), filling the card; phones keep portrait. */
export const WIDE_QUERY = "(min-width: 768px)";

/** How much of a feed video must be on screen before it starts playing by itself. */
export const AUTOPLAY_RATIO = 0.6;

// Only one video plays at a time, anywhere on the page.
let playing: HTMLMediaElement | null = null;
// Once the reader turns the sound on, later feed videos start with sound too (falling back to muted).
let soundOn = false;

/** Called when a video (or an illustrated video's narration) starts: pauses whichever one was playing before. */
export function claimPlayback(video: HTMLMediaElement) {
  if (playing && playing !== video && !playing.paused) playing.pause();
  playing = video;
}

/** Test hook: forget which video is playing and whether sound was turned on. */
export function resetPlayback() {
  playing = null;
  soundOn = false;
}

function prefersReducedMotion(): boolean {
  return typeof window !== "undefined" && !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

/** play() returns a promise in browsers (rejected when autoplay is refused); older ones return nothing. */
function tryPlay(v: HTMLVideoElement): Promise<void> {
  try {
    return Promise.resolve(v.play?.());
  } catch (err) {
    return Promise.reject(err);
  }
}

/** play() rejects with NotSupportedError when no source can be played (bad file, codec, 404). */
function isUnplayable(err: unknown): boolean {
  return err instanceof DOMException ? err.name === "NotSupportedError" : (err as { name?: string })?.name === "NotSupportedError";
}

/**
 * The card's animated explainer. The credit, licence and any health note are
 * burned into the video itself, and the card's own credit stays on the page.
 *
 * On a card's page nothing downloads until the reader presses play. In the
 * feed (`feed`), it plays muted by itself once at least 60% of it is on screen
 * and pauses when it scrolls away; tapping it toggles the sound. If the browser
 * refuses autoplay, or the reader prefers reduced motion, the Play button stays.
 *
 * Films stay dark in both modes: until it plays, the poster carries a bottom
 * fade with an amber kicker, the title in white Fraunces, and the Play button with a
 * duration pill beside it (kept off the poster's own text, which sits at the top).
 *
 * When the video can't play (the file fails to load or decode, or nothing has played
 * PLAY_TIMEOUT_MS after the reader pressed play), it says so over the poster, with
 * "Try again" and a link that opens the file on its own.
 *
 * Once it plays, a Full screen button puts the film on the whole screen with sound (an iPhone
 * opens its own player); a feed video goes back to playing muted when the reader leaves.
 */
export function ExplainerVideo({ card, feed = false }: { card: Card; feed?: boolean }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [started, setStarted] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [muted, setMuted] = useState(true);
  const [failed, setFailed] = useState(false);
  // Set while waiting for playback to begin after a press on Play or Try again.
  const [waiting, setWaiting] = useState(0);
  // The reader paused it: don't restart it until it scrolls away and back.
  const userPaused = useRef(false);
  const [fullScreen, setFullScreen] = useState(false);
  // Whether a feed video was muted before it went full screen, to put back afterwards.
  const mutedBefore = useRef(true);
  const e = card.explainer;
  const wideScreen = useMediaQuery(WIDE_QUERY);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    return onFullscreenChange(() => {
      const now = isFullscreen(v, v);
      setFullScreen((was) => {
        if (was && !now && feed && mutedBefore.current) {
          v.muted = true;
          setMuted(true);
        }
        return now;
      });
    }, v);
  }, [feed]);

  useEffect(() => {
    const v = videoRef.current;
    if (!feed || !v || typeof IntersectionObserver === "undefined" || prefersReducedMotion()) return;
    const io = new IntersectionObserver(
      (entries) => {
        const entry = entries[entries.length - 1];
        if (!entry) return;
        if (entry.isIntersecting && entry.intersectionRatio >= AUTOPLAY_RATIO) {
          // Listen mode is playing: feed videos stay still until the reader starts one.
          if (!v.paused || userPaused.current || isListeningPlaying()) return;
          v.muted = !soundOn;
          tryPlay(v).catch((err) => {
            if (isUnplayable(err)) return setFailed(true);
            if (v.muted) return; // refused even muted: the Play button stays
            v.muted = true;
            tryPlay(v).catch(() => {});
          });
        } else {
          userPaused.current = false;
          if (!v.paused) v.pause();
        }
      },
      { threshold: [0, AUTOPLAY_RATIO, 1] },
    );
    io.observe(v);
    return () => {
      io.disconnect();
      if (!v.paused) v.pause();
    };
  }, [feed]);

  // Nothing played a while after the reader asked for it: offer the fallback.
  useEffect(() => {
    if (!waiting) return;
    const t = window.setTimeout(() => {
      const v = videoRef.current;
      if (v && v.paused && v.readyState < 3) setFailed(true);
    }, PLAY_TIMEOUT_MS);
    return () => window.clearTimeout(t);
  }, [waiting]);

  if (!e) return null;
  // The cut that fits the screen: its file, poster and shape.
  const cut = wideScreen && e.landscape ? e.landscape : e;
  const wide = cut.width > cut.height;
  const videoSrc = mediaUrl(cut.video_url);
  const seconds = Math.round(e.duration_s);
  const kind = e.kind === "film" ? "Short film" : "Animated explainer";
  const duration = seconds < 60 ? `${seconds} s` : `${Math.round(seconds / 6) / 10} min`;

  function play() {
    const v = videoRef.current;
    setStarted(true);
    if (!v) return;
    userPaused.current = false;
    if (feed) {
      // A tap is a user gesture, so sound is allowed.
      v.muted = false;
      soundOn = true;
      setMuted(false);
    } else {
      v.focus();
    }
    setWaiting((n) => n + 1);
    // It can still be refused; on a card page the native controls remain.
    tryPlay(v).catch((err) => {
      if (isUnplayable(err)) setFailed(true);
    });
  }

  function retry() {
    const v = videoRef.current;
    setFailed(false);
    if (!v) return;
    v.load(); // forget the failed attempt and fetch the file again
    play();
  }

  function togglePlay() {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      userPaused.current = false;
      tryPlay(v).catch(() => {});
    } else {
      userPaused.current = true;
      v.pause();
    }
  }

  function openFullScreen() {
    const v = videoRef.current;
    if (!v) return;
    mutedBefore.current = v.muted;
    // Full screen is for watching: with sound, and playing.
    v.muted = false;
    setMuted(false);
    userPaused.current = false;
    setStarted(true);
    if (enterFullscreen(v, v)) setFullScreen(true);
    if (v.paused) {
      setWaiting((n) => n + 1);
      tryPlay(v).catch((err) => {
        if (isUnplayable(err)) setFailed(true);
      });
    } else {
      videoStarted();
    }
  }

  const fullScreenButton = (
    <button
      type="button"
      onClick={openFullScreen}
      aria-label="Full screen"
      title="Full screen"
      data-testid="video-fullscreen"
      className="pointer-events-auto grid size-11 place-items-center rounded-full bg-film/75 text-film-fg hover:bg-film"
    >
      <Icon name="fullscreen" className="size-5" />
    </button>
  );

  function toggleSound() {
    const v = videoRef.current;
    if (!v) return;
    v.muted = !v.muted;
    soundOn = !v.muted;
    setMuted(v.muted);
    if (!v.muted) videoStarted();
    if (v.paused && !userPaused.current) tryPlay(v).catch(() => {});
  }

  return (
    // In the phone feed the video leads its slide and takes whatever height the title, source,
    // "Read more" and actions leave (CardView makes the card a flex column there); the frame keeps
    // the film's shape, so it is as wide as that height allows.
    <figure
      className={`mt-6 ${feed ? "max-md:order-first max-md:mb-3 max-md:mt-0 max-md:flex max-md:min-h-0 max-md:flex-1 max-md:justify-center" : ""}`}
      data-testid="explainer"
    >
      <div
        className={`relative mx-auto w-full overflow-hidden rounded-card border border-film bg-film text-film-fg ${
          wide ? "" : "max-w-[22rem]"
        } ${feed ? "max-md:h-full max-md:w-auto max-md:max-w-full" : ""}`}
        style={feed || wide ? { aspectRatio: `${cut.width} / ${cut.height}` } : undefined}
        data-shape={wide ? "landscape" : "portrait"}
      >
        <video
          ref={videoRef}
          controls={(!feed && started) || fullScreen}
          playsInline
          muted={feed}
          loop={feed}
          preload="none"
          // No crossOrigin: the R2 media bucket sends no CORS headers, and a CORS request for the
          // file fails, which the browser reports as an unplayable video.
          src={videoSrc}
          poster={mediaUrl(cut.poster_url)}
          width={cut.width}
          height={cut.height}
          className={`block h-auto w-full bg-film ${feed ? "max-md:h-full max-md:object-contain" : ""}`}
          aria-label={`${kind}: ${card.title}`}
          onClick={feed && started ? toggleSound : undefined}
          onPlay={(ev) => {
            claimPlayback(ev.currentTarget);
            // A video with sound is one the reader chose: Listen mode pauses for it.
            if (!ev.currentTarget.muted) videoStarted();
            setStarted(true);
            setIsPlaying(true);
          }}
          onPlaying={() => {
            setFailed(false);
            setWaiting(0);
          }}
          onError={() => setFailed(true)}
          onPause={() => setIsPlaying(false)}
          onVolumeChange={(ev) => setMuted(ev.currentTarget.muted)}
        >
          {e.captions_url ? <track kind="captions" srcLang="en" label="English" src={mediaUrl(e.captions_url)} /> : null}
        </video>
        {feed && started && !failed ? (
          <div className="pointer-events-none absolute inset-x-0 bottom-0 flex justify-between p-2">
            <button
              type="button"
              onClick={togglePlay}
              aria-label={isPlaying ? "Pause video" : "Play video"}
              className="pointer-events-auto grid size-11 place-items-center rounded-full bg-film/75 text-film-fg hover:bg-film"
            >
              <svg aria-hidden="true" viewBox="0 0 12 12" className="size-3.5 fill-current">
                {isPlaying ? <path d="M2.5 1.5h2.5v9H2.5zM7 1.5h2.5v9H7z" /> : <path d="M3 1.5v9l7.5-4.5z" />}
              </svg>
            </button>
            <span className="flex gap-2">
              {fullScreenButton}
              <button
                type="button"
                onClick={toggleSound}
                aria-label={muted ? "Unmute video" : "Mute video"}
                className="pointer-events-auto grid size-11 place-items-center rounded-full bg-film/75 text-film-fg hover:bg-film"
              >
                <svg aria-hidden="true" viewBox="0 0 16 16" className="size-4 fill-none stroke-current" strokeWidth="1.5">
                  <path d="M2.5 6h2.5l3.5-3v10L5 10H2.5z" className="fill-current" />
                  {muted ? (
                    <path d="M11 6l3.5 4M14.5 6L11 10" strokeLinecap="round" />
                  ) : (
                    <path d="M11 5.5a3.5 3.5 0 0 1 0 5M12.5 3.5a6 6 0 0 1 0 9" strokeLinecap="round" />
                  )}
                </svg>
              </button>
            </span>
          </div>
        ) : null}
        {!feed && started && !failed ? <div className="absolute right-2 top-2">{fullScreenButton}</div> : null}
        {failed ? (
          <div
            role="alert"
            className="absolute inset-0 flex flex-col justify-end bg-[linear-gradient(180deg,rgba(20,17,14,0.35)_0%,rgba(20,17,14,0.94)_55%)] p-5 text-left"
          >
            <p className="font-serif text-xl font-semibold leading-snug text-film-fg">This video can&apos;t play here</p>
            <p className="mt-1 text-sm text-film-fg/80">
              Your browser couldn&apos;t load it. Try again, open the video on its own, or read the card below.
            </p>
            <div className="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={retry}
                className="inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-sm font-semibold text-accent-fg hover:brightness-105"
              >
                Try again
              </button>
              <a
                href={videoSrc}
                target="_blank"
                rel="noopener"
                className="inline-flex min-h-11 items-center rounded-full border border-film-fg/40 px-4 text-sm font-semibold text-film-fg hover:bg-film-fg/10"
              >
                Open the video
              </a>
            </div>
          </div>
        ) : started ? null : (
          <button
            type="button"
            onClick={play}
            className="group absolute inset-0 flex w-full flex-col justify-end bg-[linear-gradient(180deg,rgba(20,17,14,0)_45%,rgba(20,17,14,0.92)_75%)] p-5 text-left focus-visible:outline-offset-[-4px]"
          >
            <span className="text-[0.6875rem] font-bold uppercase tracking-[0.12em] text-accent">
              {kind}
            </span>
            <span aria-hidden="true" className="mt-1 font-serif text-xl font-semibold leading-snug text-film-fg text-balance">
              {card.title}
            </span>
            <span className="mt-3 flex items-center justify-between gap-3">
              <span className="inline-flex min-h-11 w-fit items-center gap-2 rounded-full bg-accent px-4 py-1.5 text-sm font-semibold text-accent-fg group-hover:brightness-105">
                <svg aria-hidden="true" viewBox="0 0 12 12" className="size-3 fill-current">
                  <path d="M3 1.5v9l7.5-4.5z" />
                </svg>
                Play
                <span className="sr-only"> the {kind.toLowerCase()}</span>
              </span>
              <span data-testid="explainer-duration" className="inline-flex items-center gap-1.5 rounded-full bg-film/80 px-2.5 py-1 text-xs font-semibold text-film-fg">
                <span aria-hidden="true" className="size-2 rounded-full bg-accent" />
                {duration}
              </span>
            </span>
          </button>
        )}
      </div>
    </figure>
  );
}
