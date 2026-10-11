"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { topicName } from "@/lib/content";
import { useListen } from "@/lib/listen";
import { formatTime, SLEEP_MINUTES, sourceLine, SPEEDS, type ListenPlayer, type ListenState } from "@/lib/listen-player";
import { Icon } from "./Icon";

/**
 * Listen mode's controls while a session is on, on every page: a mini-player docked above the
 * phone tab bar (at the bottom of the screen from md up) with the title, play/pause and next, and
 * the "Now listening" sheet it opens, with everything else.
 */
export function ListenDock() {
  const { player, state } = useListen();
  // The sheet is open for one session: a new session starts with it closed.
  const [openFor, setOpenFor] = useState(-1);
  const open = openFor === state.session && state.active;
  const setOpen = (on: boolean) => setOpenFor(on ? state.session : -1);
  const item = state.active ? state.items[state.index] : undefined;
  if (!player || !state.active || !item) return null;

  const pct = state.duration > 0 ? Math.min(100, (state.position / state.duration) * 100) : 0;
  return (
    <>
      <section
        data-listen-bar
        aria-label="Listen mode"
        className="fixed inset-x-0 bottom-[var(--tabbar-h)] z-10 border-t border-line bg-nav md:pb-[env(safe-area-inset-bottom,0px)]"
      >
        <div aria-hidden="true" className="absolute inset-x-0 top-0 h-0.5">
          <div className="h-full bg-accent" style={{ width: `${pct}%` }} />
        </div>
        <div className="mx-auto flex h-[calc(4rem-1px)] max-w-3xl items-center gap-1 px-2 md:px-4">
          <button
            type="button"
            onClick={() => setOpen(true)}
            aria-haspopup="dialog"
            className="flex min-h-11 min-w-0 flex-1 items-center gap-3 rounded-lg px-2 text-left hover:bg-surface-2"
          >
            <span className="grid size-10 shrink-0 place-items-center rounded-full bg-accent-soft text-accent-text">
              <Icon name="headphones" className="size-5" />
            </span>
            <span className="min-w-0">
              <span className="block truncate text-sm font-semibold">{item.card.title}</span>
              <span className="block truncate text-xs text-muted">{statusLine(state)}</span>
            </span>
            <span className="sr-only">. Open the player</span>
          </button>
          <PlayPause player={player} state={state} size="small" />
          <button
            type="button"
            onClick={() => player.next()}
            disabled={!canNext(state)}
            aria-label="Next idea"
            className="grid size-11 shrink-0 place-items-center rounded-full text-fg hover:bg-surface-2 disabled:opacity-40"
          >
            <Icon name="skipNext" className="size-6" />
          </button>
        </div>
      </section>
      <NowListening open={open} onClose={() => setOpen(false)} player={player} state={state} />
    </>
  );
}

function canNext(state: ListenState): boolean {
  if (state.phase === "finished" || state.phase === "waiting") return false;
  return !state.single;
}

function statusLine(state: ListenState): string {
  const item = state.items[state.index];
  if (state.phase === "finished") return "That's everything for now";
  if (state.phase === "waiting") return "Loading more ideas…";
  if (state.phase === "chime") return "Up next";
  if (!state.playing) return `Paused · ${item ? sourceLine(item.card) : ""}`;
  return item ? sourceLine(item.card) : "";
}

function PlayPause({ player, state, size }: { player: ListenPlayer; state: ListenState; size: "small" | "large" }) {
  const done = state.phase === "finished" || state.phase === "waiting";
  return (
    <button
      type="button"
      onClick={() => player.toggle()}
      disabled={done}
      aria-label={state.playing ? "Pause" : "Play"}
      className={`grid shrink-0 place-items-center rounded-full bg-accent text-accent-fg hover:brightness-105 disabled:opacity-40 ${
        size === "large" ? "size-16" : "size-11"
      }`}
    >
      <Icon name={state.playing ? "pause" : "play"} className={size === "large" ? "size-8" : "size-6"} />
    </button>
  );
}

function sleepValue(state: ListenState): string {
  if (!state.sleep) return "off";
  return state.sleep.kind === "card" ? "card" : String(state.sleep.minutes);
}

function clock(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

/** The full player: a sheet from the bottom on phones, a dialog on wider screens. */
function NowListening({
  open,
  onClose,
  player,
  state,
}: {
  open: boolean;
  onClose: () => void;
  player: ListenPlayer;
  state: ListenState;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  // While the reader drags the progress bar, it shows where they are dragging, not the playback.
  const [drag, setDrag] = useState<number | null>(null);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      if (typeof d.showModal === "function") d.showModal();
      else d.setAttribute("open", "");
    } else if (!open && d.open) {
      if (typeof d.close === "function") d.close();
      else d.removeAttribute("open");
    }
  }, [open]);

  const item = state.items[state.index];
  const card = item?.card;
  const position = drag ?? state.position;
  const duration = Math.max(state.duration, 0);

  function commit() {
    if (drag === null) return;
    player.seek(drag);
    setDrag(null);
  }

  return (
    <dialog
      ref={ref}
      aria-labelledby="listen-title"
      className="m-auto max-h-[calc(100dvh-2rem)] w-[min(32rem,calc(100vw-2rem))] max-w-full overflow-y-auto rounded-2xl border border-line bg-surface p-0 text-fg backdrop:bg-black/50 max-md:mb-0 max-md:max-h-[92dvh] max-md:w-full max-md:rounded-b-none max-md:border-x-0 max-md:border-b-0"
      onClose={onClose}
      onClick={(e) => {
        if (e.target === ref.current) onClose();
      }}
    >
      {open && card ? (
        <div className="p-5 pb-[calc(1.25rem+env(safe-area-inset-bottom,0px))] sm:p-6">
          <div className="flex items-start justify-between gap-3">
            <p className="eyebrow pt-3">Now listening · {topicName(card.topic)}</p>
            <button
              type="button"
              onClick={onClose}
              aria-label="Close the player"
              className="-mr-2 -mt-1 grid size-11 shrink-0 place-items-center rounded-full text-muted hover:bg-surface-2 hover:text-fg"
            >
              <Icon name="expandMore" className="size-6" />
            </button>
          </div>
          <h2 id="listen-title" className="mt-1 font-serif text-2xl font-semibold leading-tight text-balance">
            {card.title}
          </h2>
          <p className="mt-2 text-sm text-fg-2">{sourceLine(card)}</p>
          <p className="mt-1 text-xs text-muted">
            {state.voice === "recording" && card.audio?.voice_name
              ? `Voice: ${card.audio.voice_name}`
              : "Read by your device's voice"}
            {!state.single ? ` · Idea ${state.index + 1} of ${state.items.length}${state.loadingMore ? "+" : ""}` : ""}
          </p>

          <div className="mt-5">
            <input
              type="range"
              min={0}
              max={duration || 1}
              step={0.1}
              value={Math.min(position, duration || 1)}
              disabled={state.phase !== "card" || duration <= 0}
              aria-label="Position in this idea"
              aria-valuetext={`${formatTime(position)} of ${formatTime(duration)}`}
              onChange={(e) => setDrag(Number(e.currentTarget.value))}
              onPointerUp={commit}
              onKeyUp={commit}
              onBlur={commit}
              className="block h-11 w-full cursor-pointer"
            />
            <div className="flex justify-between text-xs tabular-nums text-muted" aria-hidden="true">
              <span>{formatTime(position)}</span>
              <span>{formatTime(duration)}</span>
            </div>
          </div>

          <div className="mt-3 flex items-center justify-center gap-2 sm:gap-4">
            <button
              type="button"
              onClick={() => player.previous()}
              disabled={state.phase === "finished" || state.phase === "waiting"}
              aria-label="Previous idea, or back to the start of this one"
              className="grid size-12 place-items-center rounded-full hover:bg-surface-2 disabled:opacity-40"
            >
              <Icon name="skipPrevious" className="size-7" />
            </button>
            <button
              type="button"
              onClick={() => player.back()}
              disabled={state.phase !== "card"}
              aria-label="Back 10 seconds"
              className="grid size-12 place-items-center rounded-full hover:bg-surface-2 disabled:opacity-40"
            >
              <Icon name="replay10" className="size-7" />
            </button>
            <PlayPause player={player} state={state} size="large" />
            <button
              type="button"
              onClick={() => player.next()}
              disabled={!canNext(state)}
              aria-label="Next idea"
              className="grid size-12 place-items-center rounded-full hover:bg-surface-2 disabled:opacity-40"
            >
              <Icon name="skipNext" className="size-7" />
            </button>
          </div>

          {state.phase === "finished" ? (
            <p role="status" className="mt-3 text-center text-sm text-muted">
              {state.error ?? "That's everything for now."}
            </p>
          ) : null}

          <div className="mt-5 grid gap-4 sm:grid-cols-2">
            <div role="group" aria-labelledby="listen-speed">
              <p id="listen-speed" className="label text-sm">
                Speed
              </p>
              <div className="flex gap-1.5">
                {SPEEDS.map((s) => (
                  <button
                    key={s}
                    type="button"
                    aria-pressed={state.speed === s}
                    onClick={() => player.setSpeed(s)}
                    className={`chip min-h-11 flex-1 justify-center px-2 text-sm ${state.speed === s ? "chip-on" : "hover:text-fg"}`}
                  >
                    {s}×
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label htmlFor="listen-sleep" className="label flex items-center gap-1.5 text-sm">
                <Icon name="timer" className="size-4" />
                Sleep timer
              </label>
              <select
                id="listen-sleep"
                className="field"
                value={sleepValue(state)}
                onChange={(e) => {
                  const v = e.currentTarget.value;
                  player.setSleep(v === "off" ? null : v === "card" ? "card" : Number(v));
                }}
              >
                <option value="off">Off</option>
                {SLEEP_MINUTES.map((m) => (
                  <option key={m} value={String(m)}>
                    {m} minutes
                  </option>
                ))}
                <option value="card">End of this idea</option>
              </select>
              {state.sleep?.kind === "minutes" ? (
                <p className="hint">Pauses at {clock(state.sleep.endsAt)}</p>
              ) : null}
            </div>
          </div>

          <div className="mt-6 flex flex-wrap gap-3">
            <Link href={`/ideas/${item.id}`} onClick={onClose} className="btn btn-primary flex-1">
              Open card
            </Link>
            <button
              type="button"
              onClick={() => {
                onClose();
                player.stop();
              }}
              className="btn flex-1"
            >
              <Icon name="close" className="size-4" />
              Stop listening
            </button>
          </div>
        </div>
      ) : null}
    </dialog>
  );
}
