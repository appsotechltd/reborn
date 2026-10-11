"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";

/**
 * A row of chips that scrolls sideways when it doesn't fit, with a fade on each edge
 * that has more chips beyond it, so it's clear the row scrolls. Rows that fit (or wrap,
 * on wider screens) show no fade. `trailing` sits after the row, outside the scroll, always in view.
 */
export function ChipRow({
  label,
  className = "",
  scrollClassName = "",
  trailing,
  children,
  ...rest
}: {
  label: string;
  /** Classes for the outer box (position, margins, background). */
  className?: string;
  /** Classes for the scrolling row itself (flex, gap, padding, overflow). */
  scrollClassName?: string;
  /** A control after the row that doesn't scroll with it. */
  trailing?: ReactNode;
  children: ReactNode;
} & { [data: `data-${string}`]: string | boolean | undefined }) {
  const ref = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ start: false, end: false });

  const update = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const start = el.scrollLeft > 1;
    const end = el.scrollLeft + el.clientWidth < el.scrollWidth - 1;
    setEdges((e) => (e.start === start && e.end === end ? e : { start, end }));
  }, []);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    update();
    window.addEventListener("resize", update);
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(update) : null;
    ro?.observe(el);
    return () => {
      window.removeEventListener("resize", update);
      ro?.disconnect();
    };
  }, [update]);

  const endFade = (
    <span
      aria-hidden="true"
      className={`pointer-events-none absolute inset-y-0 w-10 bg-linear-to-l from-bg to-transparent transition-opacity duration-150 ${
        trailing ? "right-full" : "right-0"
      } ${edges.end ? "opacity-100" : "opacity-0"}`}
    />
  );

  return (
    <div className={`relative ${trailing ? "flex items-center" : ""} ${className}`} {...rest}>
      <div
        ref={ref}
        role="group"
        aria-label={label}
        onScroll={update}
        data-fade-start={edges.start || undefined}
        data-fade-end={edges.end || undefined}
        className={`${trailing ? "min-w-0 flex-1" : ""} ${scrollClassName}`}
      >
        {children}
      </div>
      <span
        aria-hidden="true"
        className={`pointer-events-none absolute inset-y-0 left-0 w-10 bg-linear-to-r from-bg to-transparent transition-opacity duration-150 ${
          edges.start ? "opacity-100" : "opacity-0"
        }`}
      />
      {trailing ? (
        <div className="relative shrink-0">
          {endFade}
          {trailing}
        </div>
      ) : (
        endFade
      )}
    </div>
  );
}
