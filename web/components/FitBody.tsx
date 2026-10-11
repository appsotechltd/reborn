"use client";

import { type ReactNode, useEffect, useRef } from "react";
import { SNAP_QUERY } from "@/lib/use-snap-feed";

/** The body keeps at least this many lines when something above it (the note) can shrink. */
export const MIN_BODY_LINES = 2;

/**
 * How many whole lines of `text` fit in `room` px: every paragraph that ends inside it, plus the
 * whole lines of the first one that doesn't. Never counts a line that would be cut.
 */
export function wholeLines(text: HTMLElement, room: number, line: number): { lines: number; fits: boolean } {
  const top = text.getBoundingClientRect().top;
  let lines = 0;
  for (const p of Array.from(text.children)) {
    const r = p.getBoundingClientRect();
    if (r.bottom - top <= room + 0.5) {
      lines += Math.round(r.height / line);
      continue;
    }
    lines += Math.max(0, Math.floor((room - (r.top - top) + 0.5) / line));
    return { lines, fits: false };
  }
  return { lines, fits: true };
}

/**
 * The phone feed preview's body: takes the height it is given and shows the whole lines that fit,
 * the last one ending in "…" (as the app does), never scrolling and never showing part of a line:
 * if not one whole line fits, the body is hidden. When fewer than MIN_BODY_LINES fit, notes in the
 * same card marked `data-fit-shrink` (the health or support note) drop to one line first. Measured
 * after layout and again whenever the space changes; until then (and from md up) it is the plain
 * body, faded at the cut by the caller's class.
 */
export function FitBody({ className, children }: { className: string; children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const box = outer.current;
    const text = inner.current;
    if (!box || !text) return;
    const card = box.closest("article") ?? box.parentElement;
    const shrinkable = () => Array.from(card?.querySelectorAll<HTMLElement>("[data-fit-shrink]") ?? []);
    let settled = -1;
    const fit = () => {
      text.style.removeProperty("-webkit-line-clamp");
      text.removeAttribute("data-clamped");
      text.removeAttribute("data-fits");
      text.removeAttribute("data-empty");
      shrinkable().forEach((el) => el.removeAttribute("data-shrunk"));
      settled = -1;
      if (!window.matchMedia?.(SNAP_QUERY).matches) return;
      const line = parseFloat(getComputedStyle(text).lineHeight);
      if (!line) return;
      let { lines, fits } = wholeLines(text, box.clientHeight, line);
      if (!fits && lines < MIN_BODY_LINES && shrinkable().length) {
        shrinkable().forEach((el) => el.setAttribute("data-shrunk", ""));
        ({ lines, fits } = wholeLines(text, box.clientHeight, line));
      }
      settled = box.clientHeight;
      if (fits) text.setAttribute("data-fits", "");
      else if (lines === 0) text.setAttribute("data-empty", "");
      else {
        text.style.setProperty("-webkit-line-clamp", String(lines));
        text.setAttribute("data-clamped", "");
      }
    };
    fit();
    void document.fonts?.ready.then(fit);
    if (typeof ResizeObserver === "undefined") return;
    // Skip the notification for the size fit() itself just settled on.
    const ro = new ResizeObserver(() => {
      if (box.clientHeight !== settled) fit();
    });
    ro.observe(box);
    return () => ro.disconnect();
  }, []);

  return (
    <div ref={outer} data-card-body className={className}>
      <div ref={inner} data-fit-lines>
        {children}
      </div>
    </div>
  );
}
