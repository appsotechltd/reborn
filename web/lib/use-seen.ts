"use client";

import { useCallback, useEffect, useRef } from "react";
import type { ApiClient } from "./api";

/** How long a post must stay at least half on screen to count as seen. */
export const SEEN_AFTER_MS = 1000;
/** How long seen ids are collected before one POST /v1/seen. */
export const SEEN_BATCH_MS = 2000;
/** How long a post must stay on screen to count as read (streaks, goals). Scrolling past only marks it seen. */
export const READ_AFTER_MS = 8000;

/** True when at least half the element is visible, or it fills at least half the viewport (tall posts). */
export function isHalfVisible(entry: Pick<IntersectionObserverEntry, "isIntersecting" | "intersectionRatio" | "intersectionRect" | "rootBounds">): boolean {
  if (!entry.isIntersecting) return false;
  if (entry.intersectionRatio >= 0.5) return true;
  const root = entry.rootBounds?.height ?? (typeof window !== "undefined" ? window.innerHeight : 0);
  return root > 0 && entry.intersectionRect.height >= root * 0.5;
}

/**
 * Marks posts seen once they have been at least half on screen for about a second,
 * batching ids into POST /v1/seen, and read (POST /v1/cards/{id}/view) once they
 * have stayed on screen for READ_AFTER_MS. Returns a ref callback for elements that carry
 * `data-post-id`. Does nothing while `enabled` is false (signed out).
 */
export function useSeenTracker(api: ApiClient, enabled: boolean) {
  const elements = useRef(new Set<HTMLElement>());
  const observer = useRef<IntersectionObserver | null>(null);
  const done = useRef(new Set<string>());
  const queue = useRef(new Set<string>());
  const timers = useRef(new Map<string, number>());
  const readDone = useRef(new Set<string>());
  const readTimers = useRef(new Map<string, number>());
  const flushTimer = useRef<number | undefined>(undefined);

  const flush = useCallback(() => {
    window.clearTimeout(flushTimer.current);
    flushTimer.current = undefined;
    const all = [...queue.current];
    queue.current.clear();
    for (let i = 0; i < all.length; i += 100) {
      const ids = all.slice(i, i + 100); // the API takes at most 100 per call
      api.markSeen(ids).catch(() => {
        // Let them be counted again next time they scroll into view.
        ids.forEach((id) => done.current.delete(id));
      });
    }
  }, [api]);

  useEffect(() => {
    if (!enabled || typeof IntersectionObserver === "undefined") return;
    const timersMap = timers.current;
    const readMap = readTimers.current;
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const el = entry.target as HTMLElement;
          const id = el.dataset.postId;
          if (!id) continue;
          if (!readDone.current.has(id)) {
            if (isHalfVisible(entry)) {
              if (!readMap.has(id)) {
                readMap.set(
                  id,
                  window.setTimeout(() => {
                    readMap.delete(id);
                    readDone.current.add(id);
                    api.recordView(id).catch(() => readDone.current.delete(id));
                  }, READ_AFTER_MS),
                );
              }
            } else if (readMap.has(id)) {
              window.clearTimeout(readMap.get(id));
              readMap.delete(id);
            }
          }
          if (done.current.has(id)) continue;
          if (isHalfVisible(entry)) {
            if (timersMap.has(id)) continue;
            timersMap.set(
              id,
              window.setTimeout(() => {
                timersMap.delete(id);
                done.current.add(id);
                queue.current.add(id);
                if (flushTimer.current === undefined) flushTimer.current = window.setTimeout(flush, SEEN_BATCH_MS);
              }, SEEN_AFTER_MS),
            );
          } else if (timersMap.has(id)) {
            window.clearTimeout(timersMap.get(id));
            timersMap.delete(id);
          }
        }
      },
      { threshold: [0, 0.25, 0.5, 0.75, 1] },
    );
    observer.current = io;
    elements.current.forEach((el) => io.observe(el));
    const onHide = () => {
      if (document.visibilityState === "hidden") flush();
    };
    document.addEventListener("visibilitychange", onHide);
    window.addEventListener("pagehide", flush);
    return () => {
      io.disconnect();
      observer.current = null;
      timersMap.forEach((t) => window.clearTimeout(t));
      timersMap.clear();
      readMap.forEach((t) => window.clearTimeout(t));
      readMap.clear();
      document.removeEventListener("visibilitychange", onHide);
      window.removeEventListener("pagehide", flush);
      flush();
    };
  }, [api, enabled, flush]);

  return useCallback((el: HTMLElement | null) => {
    if (!el) return;
    elements.current.add(el);
    observer.current?.observe(el);
    return () => {
      elements.current.delete(el);
      observer.current?.unobserve(el);
    };
  }, []);
}
