"use client";

import { type ReactNode, useEffect, useRef } from "react";
import { SNAP_QUERY } from "@/lib/use-snap-feed";

/**
 * The phone feed preview's body: takes the height it is given and shows the whole lines that fit,
 * the last one ending in "…" (as the app does), never scrolling. Measured after layout and again
 * whenever the space changes; until then (and from md up) it is the plain body, faded at the cut
 * by the caller's class.
 */
export function FitBody({ className, children }: { className: string; children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const box = outer.current;
    const text = inner.current;
    if (!box || !text) return;
    const fit = () => {
      text.style.removeProperty("-webkit-line-clamp");
      text.removeAttribute("data-clamped");
      text.removeAttribute("data-fits");
      if (!window.matchMedia?.(SNAP_QUERY).matches) return;
      const room = box.clientHeight;
      const line = parseFloat(getComputedStyle(text).lineHeight);
      if (!room || !line) return;
      const top = text.getBoundingClientRect().top;
      let lines = 0;
      for (const p of Array.from(text.children)) {
        const r = p.getBoundingClientRect();
        const pLines = Math.round(r.height / line);
        if (r.bottom - top <= room + 0.5) {
          lines += pLines;
          continue;
        }
        lines += Math.max(0, Math.floor((room - (r.top - top) + 0.5) / line));
        text.style.setProperty("-webkit-line-clamp", String(Math.max(1, lines)));
        text.setAttribute("data-clamped", "");
        return;
      }
      text.setAttribute("data-fits", "");
    };
    fit();
    void document.fonts?.ready.then(fit);
    if (typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(() => fit());
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
