"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef } from "react";

/**
 * Where each link shows in the strip: "all" always, "md"/"lg" from that breakpoint up.
 * Anything not in the strip at the current width is in the "More" menu instead, so the
 * strip never clips or scrolls sideways.
 */
type Show = "all" | "md" | "lg" | "menu";

export const NAV_LINKS: { href: string; label: string; show: Show }[] = [
  { href: "/", label: "Home", show: "all" },
  { href: "/discover", label: "Discover", show: "all" },
  { href: "/search", label: "Search", show: "all" },
  { href: "/favorites", label: "Favourites", show: "md" },
  { href: "/sources", label: "Sources", show: "md" },
  { href: "/review", label: "Review", show: "lg" },
  { href: "/ask", label: "Ask", show: "lg" },
  { href: "/stashes", label: "Stashes", show: "menu" },
  { href: "/circles", label: "Circles", show: "menu" },
];

const STRIP: Record<Show, string> = {
  all: "",
  md: "hidden md:block",
  lg: "hidden lg:block",
  menu: "hidden",
};
const IN_MENU: Record<Show, string> = {
  all: "hidden",
  md: "md:hidden",
  lg: "lg:hidden",
  menu: "",
};

const isActive = (href: string, pathname: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

export function NavLinks() {
  const pathname = usePathname() ?? "/";
  const more = useRef<HTMLDetailsElement>(null);
  const moreActive = NAV_LINKS.some((l) => l.show !== "all" && isActive(l.href, pathname));

  useEffect(() => {
    const close = (e: Event) => {
      const d = more.current;
      if (!d?.open) return;
      if (e instanceof KeyboardEvent) {
        if (e.key !== "Escape") return;
        d.open = false;
        d.querySelector("summary")?.focus();
      } else if (!d.contains(e.target as Node)) {
        d.open = false;
      }
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", close);
    };
  }, []);

  return (
    <ul className="flex items-center gap-0.5 text-[0.9375rem] sm:gap-1">
      {NAV_LINKS.map((l) => {
        const active = isActive(l.href, pathname);
        return (
          <li key={l.href} className={`shrink-0 ${STRIP[l.show]}`}>
            <Link
              href={l.href}
              aria-current={active ? "page" : undefined}
              className={`inline-flex min-h-11 items-center rounded-full px-3 ${
                active ? "bg-accent-soft font-semibold text-fg" : "text-muted hover:bg-surface-2 hover:text-fg"
              }`}
            >
              {l.label}
            </Link>
          </li>
        );
      })}
      <li className="shrink-0">
        <details ref={more} className="relative" key={pathname}>
          <summary
            className={`inline-flex min-h-11 cursor-pointer list-none items-center gap-1 rounded-full px-3 [&::-webkit-details-marker]:hidden ${
              moreActive ? "bg-accent-soft font-semibold text-fg" : "text-muted hover:bg-surface-2 hover:text-fg"
            }`}
          >
            More
            <svg aria-hidden="true" viewBox="0 0 12 12" className="size-3 fill-current">
              <path d="M2.5 4.5 6 8l3.5-3.5z" />
            </svg>
          </summary>
          <ul className="absolute right-0 z-20 mt-2 w-52 rounded-xl border border-line bg-surface p-1 shadow-lg">
            {NAV_LINKS.map((l) => {
              const active = isActive(l.href, pathname);
              return (
                <li key={l.href} className={IN_MENU[l.show]}>
                  <Link
                    href={l.href}
                    aria-current={active ? "page" : undefined}
                    className={`flex min-h-11 items-center rounded-lg px-3 hover:bg-surface-2 ${active ? "font-semibold" : ""}`}
                  >
                    {l.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </details>
      </li>
    </ul>
  );
}
