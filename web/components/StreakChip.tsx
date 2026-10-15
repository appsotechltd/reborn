"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useAuth } from "@/lib/auth";
import { useFeedListen } from "@/lib/feed-listen";
import { useLoad } from "@/lib/use-load";
import { DailyBanner } from "./DailyBanner";
import { Icon } from "./Icon";
import { StreakWidget } from "./StreakWidget";

/**
 * The streak as a small flame chip in the header, as in the app. Tapping it opens today's idea and
 * the full streak (goal, the last seven days) in a sheet, so the feed's first post has its slide to itself.
 */
export function StreakChip() {
  const { ready, token, user, api } = useAuth();
  const loader = useCallback(() => api.streak(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data } = useLoad(ready && token ? loader : null);
  const [open, setOpen] = useState(false);
  if (!ready || !user) return null;
  const days = data?.current ?? 0;
  return (
    <>
      <button
        type="button"
        data-testid="streak-chip"
        aria-haspopup="dialog"
        aria-label={`${days} day streak. Open today's idea and your streak`}
        onClick={() => setOpen(true)}
        className="mx-1 inline-flex h-9 items-center gap-0.5 rounded-full border border-streak-line bg-streak pl-2 pr-3 text-sm font-bold text-streak-fg hover:brightness-105"
      >
        <Icon name="fire" className={`size-[1.125rem] ${days > 0 ? "text-accent" : "text-muted"}`} />
        {days}
      </button>
      <TodaySheet open={open} onClose={() => setOpen(false)} />
    </>
  );
}

/** Today's idea and the streak: a sheet from the bottom on phones, a dialog on wider screens. */
function TodaySheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
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
  return (
    <dialog
      ref={ref}
      aria-labelledby="today-title"
      className="m-auto w-[min(28rem,calc(100vw-2rem))] max-w-full rounded-3xl border border-line bg-bg p-0 text-fg backdrop:bg-black/50 max-md:mb-0 max-md:w-full max-md:rounded-b-none max-md:border-x-0 max-md:border-b-0"
      onClose={onClose}
      onClick={(e) => {
        if (e.target === ref.current) onClose();
      }}
    >
      {open ? (
        <div className="px-4 pb-[calc(1rem+env(safe-area-inset-bottom,0px))] pt-2.5">
          <span aria-hidden="true" className="mx-auto mb-3 block h-1 w-9 rounded-full bg-ghost-line" />
          <div className="mb-2 flex items-center justify-between">
            <h2 id="today-title" className="font-serif text-xl font-semibold">
              Today
            </h2>
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="-mr-2 grid size-11 place-items-center rounded-full text-muted hover:bg-surface-2 hover:text-fg"
            >
              <Icon name="close" className="size-5" />
            </button>
          </div>
          <DailyBanner onOpen={onClose} />
          <StreakWidget variant="compact" />
        </div>
      ) : null}
    </dialog>
  );
}

/** The home feed's Listen, in the header on phones while the feed has something to play. */
export function HeaderListenButton() {
  const listen = useFeedListen();
  if (!listen) return null;
  return (
    <button
      type="button"
      onClick={listen}
      aria-label="Listen to this feed"
      className="grid size-11 place-items-center rounded-full text-accent-text hover:bg-surface-2 md:hidden"
    >
      <Icon name="headphones" className="size-6" />
    </button>
  );
}
