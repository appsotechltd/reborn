"use client";

import { useEffect, useRef, useState } from "react";
import { mediaUrl } from "@/lib/config";
import { videoStarted } from "@/lib/media-focus";
import { kenBurns, sceneAt, sceneOpacities, sceneProgress, videoDuration } from "@/lib/studio";
import type { CardVideo } from "@/lib/types";
import { claimPlayback } from "./ExplainerVideo";
import { Icon } from "./Icon";

function prefersReducedMotion(): boolean {
  return typeof window !== "undefined" && !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

function clock(s: number): string {
  const t = Math.max(0, Math.round(s));
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
}

/**
 * A member card's illustrated video: the narration plays while the card's illustrations show in
 * turn, each for an equal share of it, drifting slowly (a Ken Burns zoom and pan) and cross-fading
 * into the next. No captions or text on the pictures. A 2:3 frame that stays dark in both themes.
 * Nothing downloads until the reader presses play.
 */
export function IllustratedVideo({ video, title, feed = false }: { video: CardVideo; title: string; feed?: boolean }) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [started, setStarted] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [audioDuration, setAudioDuration] = useState<number | null>(null);
  const [failed, setFailed] = useState(false);
  // Readers who prefer reduced motion get the cross-fades without the drift.
  const [still, setStill] = useState(false);

  // Follow the narration every frame while it plays, so the drift and fades are smooth.
  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    const tick = () => {
      const a = audioRef.current;
      if (a) setTime(a.currentTime);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing]);

  const scenes = video.scenes ?? [];
  const total = videoDuration(audioDuration, video.duration_s);
  const opacities = sceneOpacities(time, total, scenes.length);
  const current = sceneAt(time, total, scenes.length);

  function toggle() {
    const a = audioRef.current;
    if (!a) return;
    if (!started) setStill(prefersReducedMotion());
    setStarted(true);
    if (a.paused) {
      setFailed(false);
      Promise.resolve(a.play?.()).catch((err: unknown) => {
        if ((err as { name?: string })?.name === "NotSupportedError") setFailed(true);
      });
    } else {
      a.pause();
    }
  }

  function seek(to: number) {
    const a = audioRef.current;
    if (!a) return;
    a.currentTime = to;
    setTime(to);
  }

  return (
    <figure
      className={`mt-6 ${feed ? "max-md:order-first max-md:mb-3 max-md:mt-0 max-md:flex max-md:min-h-0 max-md:flex-1 max-md:justify-center" : ""}`}
      data-testid="illustrated-video"
    >
      <div
        className={`relative mx-auto aspect-[2/3] w-full max-w-[22rem] overflow-hidden rounded-card border border-film bg-film text-film-fg ${
          feed ? "max-md:h-full max-md:w-auto max-md:max-w-full" : ""
        }`}
      >
        {scenes.map((s, i) => {
          const kb = still ? { scale: 1.04, x: 0, y: 0 } : kenBurns(i, sceneProgress(i, time, total, scenes.length));
          return (
            // eslint-disable-next-line @next/next/no-img-element -- media comes from R2, not next/image's optimiser
            <img
              key={s.url}
              src={mediaUrl(s.url)}
              alt=""
              loading={i === 0 ? "lazy" : started ? "eager" : "lazy"}
              decoding="async"
              data-scene={i}
              className="absolute inset-0 size-full object-cover will-change-transform"
              style={{
                opacity: opacities[i],
                transform: `scale(${kb.scale}) translate(${kb.x}%, ${kb.y}%)`,
              }}
            />
          );
        })}
        <audio
          ref={audioRef}
          data-video-audio
          src={mediaUrl(video.audio_url)}
          preload="none"
          onLoadedMetadata={(e) => setAudioDuration(e.currentTarget.duration)}
          onPlay={(e) => {
            claimPlayback(e.currentTarget);
            videoStarted();
            setPlaying(true);
          }}
          onPause={() => setPlaying(false)}
          onEnded={(e) => {
            setPlaying(false);
            setTime(e.currentTarget.duration || total);
          }}
          onError={() => started && setFailed(true)}
        />
        <span className="sr-only" aria-live="off">
          {`Illustrated video: ${title}. Picture ${current + 1} of ${scenes.length}.`}
        </span>

        {!started ? (
          <button
            type="button"
            onClick={toggle}
            className="group absolute inset-0 flex w-full flex-col justify-end bg-[linear-gradient(180deg,rgba(20,17,14,0)_55%,rgba(20,17,14,0.85)_85%)] p-5 text-left focus-visible:outline-offset-[-4px]"
          >
            <span className="flex items-center justify-between gap-3">
              <span className="inline-flex min-h-11 w-fit items-center gap-2 rounded-full bg-accent px-4 py-1.5 text-sm font-semibold text-accent-fg group-hover:brightness-105">
                <Icon name="play" className="size-4" />
                Play
                <span className="sr-only"> the illustrated video: {title}</span>
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-film/80 px-2.5 py-1 text-xs font-semibold text-film-fg">
                <span aria-hidden="true" className="size-2 rounded-full bg-accent" />
                {clock(total)}
              </span>
            </span>
          </button>
        ) : (
          <div className="absolute inset-x-0 bottom-0 flex items-center gap-2 bg-[linear-gradient(180deg,rgba(20,17,14,0)_0%,rgba(20,17,14,0.8)_60%)] p-2 pt-6">
            <button
              type="button"
              onClick={toggle}
              aria-label={playing ? "Pause video" : "Play video"}
              className="grid size-11 shrink-0 place-items-center rounded-full bg-film/75 text-film-fg hover:bg-film"
            >
              <Icon name={playing ? "pause" : "play"} className="size-5" />
            </button>
            <input
              type="range"
              min={0}
              max={total || 1}
              step={0.1}
              value={Math.min(time, total || 1)}
              onChange={(e) => seek(Number(e.target.value))}
              aria-label="Position"
              aria-valuetext={`${clock(time)} of ${clock(total)}`}
              className="h-1 min-w-0 flex-1 cursor-pointer accent-[#e9a23b]"
            />
            <span className="shrink-0 pr-1 text-xs tabular-nums text-film-fg/85">
              {clock(time)} / {clock(total)}
            </span>
          </div>
        )}
        {failed ? (
          <div role="alert" className="absolute inset-x-0 top-0 bg-film/85 p-3 text-sm text-film-fg">
            This video can&apos;t play here right now. Read the card below.
          </div>
        ) : null}
      </div>
    </figure>
  );
}
