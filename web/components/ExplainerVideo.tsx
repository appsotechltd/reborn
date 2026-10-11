"use client";

import { useEffect, useRef, useState } from "react";
import { mediaUrl } from "@/lib/config";
import type { Card } from "@/lib/types";

/** How much of a feed video must be on screen before it starts playing by itself. */
export const AUTOPLAY_RATIO = 0.6;

// Only one video plays at a time, anywhere on the page.
let playing: HTMLVideoElement | null = null;
// Once the reader turns the sound on, later feed videos start with sound too (falling back to muted).
let soundOn = false;

/** Called when a video starts: pauses whichever one was playing before. */
export function claimPlayback(video: HTMLVideoElement) {
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
 * fade with an amber kicker, the title in white Fraunces and a duration pill.
 */
export function ExplainerVideo({ card, feed = false }: { card: Card; feed?: boolean }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [started, setStarted] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [muted, setMuted] = useState(true);
  // The reader paused it: don't restart it until it scrolls away and back.
  const userPaused = useRef(false);
  const e = card.explainer;

  useEffect(() => {
    const v = videoRef.current;
    if (!feed || !v || typeof IntersectionObserver === "undefined" || prefersReducedMotion()) return;
    const io = new IntersectionObserver(
      (entries) => {
        const entry = entries[entries.length - 1];
        if (!entry) return;
        if (entry.isIntersecting && entry.intersectionRatio >= AUTOPLAY_RATIO) {
          if (!v.paused || userPaused.current) return;
          v.muted = !soundOn;
          tryPlay(v).catch(() => {
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

  if (!e) return null;
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
    // It can still be refused; on a card page the native controls remain.
    tryPlay(v).catch(() => {});
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

  function toggleSound() {
    const v = videoRef.current;
    if (!v) return;
    v.muted = !v.muted;
    soundOn = !v.muted;
    setMuted(v.muted);
    if (v.paused && !userPaused.current) tryPlay(v).catch(() => {});
  }

  return (
    // In the phone feed the video leads its slide (CardView makes the card a flex column there).
    <figure className={`mt-6 ${feed ? "max-md:order-first max-md:mb-4 max-md:mt-0" : ""}`} data-testid="explainer">
      <div
        className={`relative mx-auto w-full max-w-[22rem] overflow-hidden rounded-card border border-film bg-film text-film-fg ${
          feed ? "max-md:w-fit max-md:max-w-full" : ""
        }`}
      >
        <video
          ref={videoRef}
          controls={!feed && started}
          playsInline
          muted={feed}
          loop={feed}
          preload="none"
          crossOrigin="anonymous"
          poster={mediaUrl(e.poster_url)}
          width={e.width}
          height={e.height}
          className={`block h-auto w-full bg-film ${
            feed ? "max-md:max-h-[calc(var(--slide-h)-12rem)] max-md:w-auto max-md:max-w-full" : ""
          }`}
          aria-label={`${kind}: ${card.title}`}
          onClick={feed && started ? toggleSound : undefined}
          onPlay={(ev) => {
            claimPlayback(ev.currentTarget);
            setStarted(true);
            setIsPlaying(true);
          }}
          onPause={() => setIsPlaying(false)}
          onVolumeChange={(ev) => setMuted(ev.currentTarget.muted)}
        >
          <source src={mediaUrl(e.video_url)} type="video/mp4" />
          {e.captions_url ? <track kind="captions" srcLang="en" label="English" src={mediaUrl(e.captions_url)} /> : null}
        </video>
        {feed && started ? (
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
          </div>
        ) : null}
        {started ? null : (
          <button
            type="button"
            onClick={play}
            className="group absolute inset-0 flex w-full flex-col justify-end bg-[linear-gradient(180deg,rgba(20,17,14,0)_45%,rgba(20,17,14,0.92)_75%)] p-5 text-left focus-visible:outline-offset-[-4px]"
          >
            <span className="absolute right-3 top-3 inline-flex items-center gap-1.5 rounded-full bg-film/80 px-2.5 py-1 text-xs font-semibold text-film-fg">
              <span aria-hidden="true" className="size-2 rounded-full bg-accent" />
              {duration}
            </span>
            <span className="text-[0.6875rem] font-bold uppercase tracking-[0.12em] text-accent">
              {kind}
            </span>
            <span aria-hidden="true" className="mt-1 font-serif text-xl font-semibold leading-snug text-film-fg text-balance">
              {card.title}
            </span>
            <span className="mt-3 inline-flex min-h-11 w-fit items-center gap-2 rounded-full bg-accent px-4 py-1.5 text-sm font-semibold text-accent-fg group-hover:brightness-105">
              <svg aria-hidden="true" viewBox="0 0 12 12" className="size-3 fill-current">
                <path d="M3 1.5v9l7.5-4.5z" />
              </svg>
              Play
              <span className="sr-only"> the {kind.toLowerCase()}</span>
            </span>
          </button>
        )}
      </div>
    </figure>
  );
}
