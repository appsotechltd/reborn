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

/** The sticky bars above the feed: the site header and, on phones, the feed's topic chips. */
const STICKY = ["[data-site-header]", "[data-feed-chips]"];

/** How much of the top of the screen the sticky bars cover: where a slide's top lines up. */
export function headerHeight(): number {
  let h = 0;
  for (const sel of STICKY) {
    const el = document.querySelector<HTMLElement>(sel);
    if (el) h += el.getBoundingClientRect().height;
  }
  return h;
}

/**
 * Index of the post on screen in a feed list (its direct children): the first one still mostly
 * below the sticky bars. 0 when the list hasn't been laid out (or nothing is scrolled).
 */
export function postOnScreen(list: HTMLElement | null): number {
  if (!list) return 0;
  const offset = headerHeight();
  const slides = Array.from(list.children).filter((c): c is HTMLElement => c instanceof HTMLElement);
  const i = slides.findIndex((s) => {
    const r = s.getBoundingClientRect();
    return r.bottom - offset > Math.min(r.height / 2, 160);
  });
  return Math.max(0, i);
}

function reducedMotion(): boolean {
  return !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Keeps `--header-h` on <html> equal to the height of the sticky bars above the feed (the
 * header plus, on phones, the topic chips), so each slide can be exactly the screen below
 * them (`--slide-h`) and snapping lines slides up under them. `--site-header-h` is the
 * header alone, where the chips stick.
 */
export function useHeaderHeightVar() {
  useEffect(() => {
    const header = document.querySelector<HTMLElement>("[data-site-header]");
    if (!header) return;
    const root = document.documentElement;
    const set = () => {
      root.style.setProperty("--site-header-h", `${Math.round(header.getBoundingClientRect().height)}px`);
      root.style.setProperty("--header-h", `${Math.round(headerHeight())}px`);
    };
    const clear = () => {
      root.style.removeProperty("--header-h");
      root.style.removeProperty("--site-header-h");
    };
    set();
    if (typeof ResizeObserver === "undefined") return clear;
    const ro = new ResizeObserver(set);
    for (const sel of STICKY) {
      const el = document.querySelector<HTMLElement>(sel);
      if (el) ro.observe(el);
    }
    return () => {
      ro.disconnect();
      clear();
    };
  }, []);
}

/**
 * On narrow screens, ArrowDown/ArrowUp, PageDown/PageUp and j/k move exactly one post
 * in the snap feed (the list's direct <li> children), wherever focus is inside a post
 * (each post fits its slide, so nothing scrolls inside one). Smooth unless the reader
 * prefers reduced motion.
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
