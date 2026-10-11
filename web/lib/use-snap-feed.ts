"use client";

import { type RefObject, useEffect, useRef } from "react";

/** Below Tailwind's md breakpoint the home timeline is a full-screen, one-post-per-screen feed. */
export const SNAP_QUERY = "(max-width: 767.98px)";

/** How long a keyboard move is treated as still in flight (smooth scrolling), so quick presses keep going. */
const MOVE_MS = 700;

/** +1 / -1 for the keys that move one post, 0 for anything else. */
export function keyDirection(key: string): 1 | -1 | 0 {
  switch (key) {
    case "ArrowDown":
    case "PageDown":
    case "j":
      return 1;
    case "ArrowUp":
    case "PageUp":
    case "k":
      return -1;
    default:
      return 0;
  }
}

/**
 * Which slide is current, given each slide's top relative to the bottom of the sticky
 * header: the last one whose top has reached it. -1 while the feed hasn't reached the
 * top yet (the intro above it is showing).
 */
export function currentSlide(tops: number[], tolerance = 8): number {
  let current = -1;
  for (let i = 0; i < tops.length; i++) {
    if (tops[i] <= tolerance) current = i;
    else break;
  }
  return current;
}

function isTyping(el: EventTarget | null): boolean {
  if (!(el instanceof HTMLElement)) return false;
  if (el.isContentEditable) return true;
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || !!el.closest("[role=dialog],dialog,[role=menu]");
}

/** True when `el` can still scroll in direction `dir` (a long card inside its slide). */
function canScroll(el: Element, dir: 1 | -1): boolean {
  if (el.scrollHeight <= el.clientHeight + 1) return false;
  return dir > 0 ? el.scrollTop + el.clientHeight < el.scrollHeight - 1 : el.scrollTop > 0;
}

export function headerHeight(): number {
  const header = document.querySelector<HTMLElement>("[data-site-header]");
  return header ? header.getBoundingClientRect().height : 0;
}

function reducedMotion(): boolean {
  return !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Keeps `--header-h` on <html> equal to the sticky header's height, so each slide can be
 * exactly one screen below it (`--slide-h`) and snapping lines slides up under it.
 */
export function useHeaderHeightVar() {
  useEffect(() => {
    const header = document.querySelector<HTMLElement>("[data-site-header]");
    if (!header) return;
    const root = document.documentElement;
    const set = () => root.style.setProperty("--header-h", `${Math.round(header.getBoundingClientRect().height)}px`);
    set();
    if (typeof ResizeObserver === "undefined") return () => root.style.removeProperty("--header-h");
    const ro = new ResizeObserver(set);
    ro.observe(header);
    return () => {
      ro.disconnect();
      root.style.removeProperty("--header-h");
    };
  }, []);
}

/**
 * On narrow screens, ArrowDown/ArrowUp, PageDown/PageUp and j/k move exactly one post
 * in the snap feed (the list's direct <li> children). Arrow keys first scroll a long
 * card that has focus inside its slide. Smooth unless the reader prefers reduced motion.
 * Calls `onMove` with the index moved to (the timeline uses it to preload).
 */
export function useSnapFeedKeys(listRef: RefObject<HTMLElement | null>, onMove?: (index: number, count: number) => void) {
  const pending = useRef<{ index: number; at: number } | null>(null);
  const move = useRef(onMove);
  useEffect(() => {
    move.current = onMove;
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
      const dir = keyDirection(e.key);
      if (!dir || !window.matchMedia?.(SNAP_QUERY).matches) return;
      const list = listRef.current;
      if (!list || isTyping(e.target)) return;
      if (e.key.startsWith("Arrow") && e.target instanceof Element) {
        const scroller = e.target.closest("[data-slide-scroll]");
        if (scroller && canScroll(scroller, dir)) return;
      }
      const slides = Array.from(list.children).filter((c): c is HTMLElement => c instanceof HTMLElement);
      if (!slides.length) return;
      const offset = headerHeight();
      const now = Date.now();
      const from =
        pending.current && now - pending.current.at < MOVE_MS
          ? pending.current.index
          : currentSlide(slides.map((s) => s.getBoundingClientRect().top - offset));
      const next = from + dir;
      // Above the first post (the intro) or past the last: leave the key to the browser.
      if (next < 0 || next >= slides.length) return;
      e.preventDefault();
      pending.current = { index: next, at: now };
      slides[next].scrollIntoView({ block: "start", behavior: reducedMotion() ? "auto" : "smooth" });
      // Keep focus with the post on screen, so Tab carries on from there.
      slides[next].querySelector<HTMLElement>("h2 a")?.focus({ preventScroll: true });
      move.current?.(next, slides.length);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [listRef]);
}
