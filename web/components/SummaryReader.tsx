"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type TouchEvent } from "react";
import { useAuth } from "@/lib/auth";
import { useListenFollow, useListenMove } from "@/lib/listen";
import { itemsFromCards } from "@/lib/listen-player";
import { smoothScroll } from "@/lib/use-snap-feed";
import { subjectHref } from "@/lib/subjects";
import { localProgress, resumeIndex, saveLocalProgress, summaryHref } from "@/lib/summaries";
import type { SummaryDetail } from "@/lib/types";
import { CardView } from "./CardView";
import { Icon } from "./Icon";
import { ListenSummaryButton, SummaryProgressBar } from "./SummaryPost";

export type SummaryView = "parts" | "all";

/** A horizontal swipe longer than this (px), and wider than it is tall, turns the page. */
const SWIPE_PX = 60;
/** Saving the place waits this long after the last page turn. */
const SAVE_DELAY_MS = 600;

/**
 * Reads a summary: one part per screen with a progress bar (swipe, the arrow keys or the buttons
 * turn the page), or every part on one long page ("Read it all"). Opens where the reader stopped
 * unless the link names a part, and keeps their place as they go: through the API when signed
 * in, in this browser otherwise.
 */
export function SummaryReader({
  summary,
  initialView = "parts",
  initialPart = null,
}: {
  summary: SummaryDetail;
  initialView?: SummaryView;
  /** Zero-based part named in the link (?part=), or null to resume. */
  initialPart?: number | null;
}) {
  const { token, api } = useAuth();
  const parts = summary.parts;
  const last = parts.length - 1;
  const [view, setView] = useState<SummaryView>(initialView);
  // parts.length is the "finished" screen after the last part.
  const [index, setIndex] = useState(() => Math.max(0, Math.min(last, initialPart ?? 0)));
  const [resumedAt, setResumedAt] = useState<number | null>(null);
  const [ready, setReady] = useState(false);
  const topRef = useRef<HTMLDivElement>(null);
  const allRef = useRef<HTMLOListElement>(null);
  const touch = useRef<{ x: number; y: number } | null>(null);

  // Where to open: the part in the link, else where this reader stopped.
  useEffect(() => {
    let cancelled = false;
    async function load() {
      let saved = localProgress(summary.id);
      if (token) {
        try {
          const fresh = await api.summary(summary.id);
          if (fresh.viewer?.started) saved = fresh.viewer;
        } catch {
          // Fall back to this browser's place.
        }
      }
      if (cancelled) return;
      if (initialPart == null) {
        const at = resumeIndex(saved, parts.length);
        if (at > 0) {
          setIndex(at);
          setResumedAt(at);
        }
      }
      setReady(true);
    }
    void load();
    return () => {
      cancelled = true;
    };
    // Once per summary and reader.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [summary.id, token]);

  // Keep the place (after the opening place is known, so opening never overwrites it).
  useEffect(() => {
    if (!ready) return;
    const position = Math.min(index, last);
    const finished = index >= last;
    const url = summaryHref(summary.id, { part: view === "parts" && index <= last ? index + 1 : undefined, view: view === "all" ? "all" : undefined });
    window.history.replaceState(window.history.state, "", url);
    saveLocalProgress(summary.id, position, finished);
    const t = window.setTimeout(() => {
      if (token) api.setSummaryProgress(summary.id, position, finished).catch(() => {});
    }, SAVE_DELAY_MS);
    return () => window.clearTimeout(t);
  }, [ready, index, view, last, summary.id, token, api]);

  // While a session is on, it follows the part on screen (once the opening place is known).
  useListenFollow(
    ready && index <= last ? { items: itemsFromCards(parts), index, queue: `summary:${summary.id}` } : null,
  );

  const go = useCallback(
    (to: number) => {
      const next = Math.max(0, Math.min(parts.length, to));
      if (next === index) return;
      // Moving past a part counts as reading it.
      if (token && next > index && index <= last) api.recordView(parts[index].id).catch(() => {});
      setIndex(next);
      setResumedAt(null);
      const top = topRef.current;
      if (top && top.getBoundingClientRect().top < 0) top.scrollIntoView({ block: "start" });
    },
    [api, index, last, parts, token],
  );

  // The audio moving on to another part turns to it (or, on the long page, scrolls to it).
  useListenMove((item) => {
    const i = parts.findIndex((c) => c.id === item.card.id);
    if (i < 0 || !ready) return;
    if (view === "all") allRef.current?.querySelector(`[data-part="${i}"]`)?.scrollIntoView({ block: "start", behavior: smoothScroll() });
    else go(i);
  });

  // On the long page, the furthest part scrolled into view is the place.
  useEffect(() => {
    const list = allRef.current;
    if (view !== "all" || !list || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          const n = Number((e.target as HTMLElement).dataset.part);
          if (e.isIntersecting && n >= 0) setIndex((i) => (i > last ? i : Math.max(i, n)));
        }
      },
      { rootMargin: "0px 0px -60% 0px" },
    );
    list.querySelectorAll("[data-part]").forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, [view, last]);

  useEffect(() => {
    if (view !== "parts") return;
    function onKey(e: KeyboardEvent) {
      const el = e.target instanceof Element ? e.target : null;
      if (e.altKey || e.ctrlKey || e.metaKey || el?.closest("input, textarea, select, [contenteditable=true]")) return;
      if (e.key === "ArrowRight") go(index + 1);
      else if (e.key === "ArrowLeft") go(index - 1);
      else return;
      e.preventDefault();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [view, index, go]);

  function onTouchStart(e: TouchEvent) {
    const t = e.touches[0];
    touch.current = t ? { x: t.clientX, y: t.clientY } : null;
  }
  function onTouchEnd(e: TouchEvent) {
    const start = touch.current;
    const t = e.changedTouches[0];
    touch.current = null;
    if (!start || !t) return;
    const dx = t.clientX - start.x;
    const dy = t.clientY - start.y;
    if (Math.abs(dx) < SWIPE_PX || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    go(dx < 0 ? index + 1 : index - 1);
  }

  return (
    <div ref={topRef} className="scroll-mt-24">
      <div className="sticky top-[var(--site-header-h,3.5rem)] z-[4] -mx-4 border-b border-line bg-bg/95 px-4 py-3 backdrop-blur sm:mx-0 sm:rounded-b-inset">
        <div className="mx-auto flex max-w-read flex-wrap items-center gap-x-4 gap-y-2">
          <div className="min-w-48 flex-1">
            {view === "parts" ? (
              <SummaryProgressBar
                progress={{ started: true, position: Math.min(index, last), finished: index > last }}
                parts={parts.length}
              />
            ) : (
              <p className="text-sm text-muted">All {parts.length} parts on one page</p>
            )}
          </div>
          <div role="group" aria-label="View" className="inline-flex rounded-full border border-line p-1">
            {(
              [
                ["parts", "One at a time", "arrowForward"],
                ["all", "Read it all", "notes"],
              ] as const
            ).map(([id, label, icon]) => (
              <button
                key={id}
                type="button"
                aria-pressed={view === id}
                onClick={() => {
                  setView(id);
                  if (id === "parts" && index > last) setIndex(last);
                }}
                className={`inline-flex min-h-9 items-center gap-1.5 rounded-full px-3 text-sm pointer-coarse:min-h-11 ${
                  view === id ? "bg-chip-on font-semibold text-chip-on-fg" : "text-muted hover:text-fg"
                }`}
              >
                <Icon name={icon} className="size-4" />
                {label}
              </button>
            ))}
          </div>
          <ListenSummaryButton summaryId={summary.id} parts={parts} from={Math.min(index, last)} />
        </div>
      </div>

      {resumedAt != null && view === "parts" ? (
        <p role="status" className="mx-auto mt-4 flex max-w-read flex-wrap items-center gap-2 text-sm text-muted">
          Picking up where you left off, at part {resumedAt + 1}.
          <button type="button" className="link" onClick={() => go(0)}>
            Start from the beginning
          </button>
        </p>
      ) : null}

      {view === "all" ? (
        <ol ref={allRef} className="mt-8 grid gap-10" aria-label="All parts">
          {parts.map((card, i) => (
            <li key={card.id} id={`part-${i + 1}`} data-part={i} className="panel scroll-mt-40 px-5 py-6 sm:px-8 sm:py-8">
              <p className="mx-auto mb-3 max-w-read text-sm font-semibold text-accent-text">
                Part {i + 1} of {parts.length}
              </p>
              <CardView card={card} headingLevel="h2" />
            </li>
          ))}
          <li>
            <Finished summary={summary} onRestart={() => setView("parts")} />
          </li>
        </ol>
      ) : index > last ? (
        <Finished
          summary={summary}
          onRestart={() => go(0)}
          onReadAll={() => setView("all")}
        />
      ) : (
        <section
          aria-label={`Part ${index + 1} of ${parts.length}`}
          className="panel mt-6 touch-pan-y px-5 py-6 sm:px-8 sm:py-8"
          onTouchStart={onTouchStart}
          onTouchEnd={onTouchEnd}
          data-summary-part={index + 1}
        >
          <p className="mx-auto mb-3 max-w-read text-sm font-semibold text-accent-text">
            Part {index + 1} of {parts.length}
          </p>
          <CardView key={parts[index].id} card={parts[index]} headingLevel="h2" />
          <nav aria-label="Parts" className="mx-auto mt-8 flex max-w-read items-center justify-between gap-3">
            <button type="button" className="btn" onClick={() => go(index - 1)} disabled={index === 0}>
              <Icon name="chevronLeft" className="size-5" />
              Previous
            </button>
            <button type="button" className="btn btn-primary" onClick={() => go(index + 1)}>
              {index === last ? "Finish" : "Next"}
              <Icon name="chevronRight" className="size-5" />
            </button>
          </nav>
          <p className="mt-3 text-center text-xs text-muted md:hidden">Swipe left or right to turn the page</p>
        </section>
      )}
    </div>
  );
}

function Finished({
  summary,
  onRestart,
  onReadAll,
}: {
  summary: SummaryDetail;
  onRestart: () => void;
  onReadAll?: () => void;
}) {
  const subject = summary.subject;
  return (
    <section aria-label="Finished" className="panel mx-auto mt-6 max-w-read px-6 py-8 text-center" data-summary-finished>
      <p className="font-serif text-2xl font-semibold">You&apos;ve finished {summary.title}</p>
      <p className="mt-2 text-muted">
        {summary.parts.length} parts, about {summary.minutes} minutes of big ideas.
      </p>
      <div className="mt-5 flex flex-wrap justify-center gap-3">
        <button type="button" className="btn" onClick={onRestart}>
          Start again
        </button>
        {onReadAll ? (
          <button type="button" className="btn" onClick={onReadAll}>
            Read it all
          </button>
        ) : null}
        {summary.source ? (
          <Link href={`/sources/${summary.source.id}`} className="btn">
            About the book
          </Link>
        ) : null}
        {subject ? null : (
          <Link href="/summaries" className="btn btn-primary">
            More summaries
          </Link>
        )}
      </div>
      {subject ? (
        <div className="mt-6 border-t border-line pt-6" data-subject-next>
          <p className="text-sm text-muted">
            Guide {subject.step} of {subject.count} in{" "}
            <Link href={subjectHref(subject.id)} className="link">
              {subject.title}
            </Link>
          </p>
          {subject.next ? (
            <Link href={summaryHref(subject.next.id)} className="btn btn-primary mt-3 max-w-full">
              <span className="min-w-0 truncate">Next guide: {subject.next.title}</span>
              <Icon name="arrowForward" className="size-5" />
            </Link>
          ) : (
            <Link href={subjectHref(subject.id)} className="btn btn-primary mt-3 max-w-full">
              <Icon name="arrowBack" className="size-5" />
              <span className="min-w-0 truncate">Back to {subject.title}</span>
            </Link>
          )}
        </div>
      ) : null}
    </section>
  );
}
