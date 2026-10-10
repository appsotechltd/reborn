"use client";

import { useEffect, useRef } from "react";

/** Calls `onVisible` when scrolled near; also renders a button for keyboard users and old browsers. */
export function LoadMoreSentinel({
  onVisible,
  loading,
  label = "Load more",
}: {
  onVisible: () => void;
  loading: boolean;
  label?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const cb = useRef(onVisible);
  useEffect(() => {
    cb.current = onVisible;
  });

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) cb.current();
      },
      { rootMargin: "800px 0px" },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <div ref={ref} className="mt-6 text-center">
      <button type="button" className="btn" onClick={() => cb.current()} disabled={loading}>
        {loading ? "Loading…" : label}
      </button>
    </div>
  );
}
