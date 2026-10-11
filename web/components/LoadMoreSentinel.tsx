"use client";

import { useEffect, useRef } from "react";

/**
 * Calls `onVisible` when scrolled near; also renders a button for keyboard users and old browsers.
 *
 * The observer is re-armed every time a load finishes, so if the new page was short (or empty)
 * and the sentinel is still in range it asks again instead of stalling. After a failed load
 * (`error` set) it stops asking on its own and offers "Try again", and retries by itself when
 * the browser comes back online.
 */
export function LoadMoreSentinel({
  onVisible,
  loading,
  label = "Load more",
  error = null,
  rootMargin = "800px 0px",
}: {
  onVisible: () => void;
  loading: boolean;
  label?: string;
  /** The last load failed: show this with a retry button instead of loading automatically. */
  error?: string | null;
  /** How far ahead of the viewport to start loading (IntersectionObserver rootMargin). */
  rootMargin?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const cb = useRef(onVisible);
  useEffect(() => {
    cb.current = onVisible;
  });

  const failed = !!error;
  useEffect(() => {
    const el = ref.current;
    if (!el || loading || failed || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) cb.current();
      },
      { rootMargin },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [loading, failed, rootMargin]);

  useEffect(() => {
    if (!failed) return;
    const retry = () => cb.current();
    window.addEventListener("online", retry);
    return () => window.removeEventListener("online", retry);
  }, [failed]);

  return (
    <div ref={ref} className="mt-6 text-center" data-testid="load-more">
      {error ? (
        <p role="alert" className="mb-3 text-sm text-bad">
          {error}
        </p>
      ) : null}
      <button type="button" className="btn" onClick={() => cb.current()} disabled={loading}>
        {loading ? "Loading…" : error ? "Try again" : label}
      </button>
    </div>
  );
}
