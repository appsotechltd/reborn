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

export const NAV_LINKS: { href: string; label: string; show: Show; match?: string[] }[] = [
  { href: "/", label: "Home", show: "all" },
  { href: "/discover", label: "Discover", show: "all" },
  { href: "/search", label: "Search", show: "all" },
  { href: "/favorites", label: "Favourites", show: "md" },
  // The Library: its Books tab is /sources, its Authors tab /authors (and their pages).
  { href: "/sources", label: "Library", show: "md", match: ["/sources", "/authors"] },
  { href: "/review", label: "Review", show: "lg" },
  { href: "/ask", label: "Ask", show: "lg" },
  { href: "/ai", label: "Reborn AI", show: "menu" },
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

const MORE_ACTIVE: Record<Show, string> = {
  all: "",
  md: "max-md:bg-accent-soft max-md:font-semibold max-md:text-fg text-muted md:hover:bg-surface-2 md:hover:text-fg",
  lg: "max-lg:bg-accent-soft max-lg:font-semibold max-lg:text-fg text-muted lg:hover:bg-surface-2 lg:hover:text-fg",
  menu: "bg-accent-soft font-semibold text-fg",
};

const isActive = ({ href, match }: { href: string; match?: string[] }, pathname: string) =>
  href === "/" ? pathname === "/" : (match ?? [href]).some((m) => pathname.startsWith(m));

export function NavLinks() {
  const pathname = usePathname() ?? "/";
  const more = useRef<HTMLDetailsElement>(null);
  // "More" is marked only at the widths where the current page's link is in it.
  const inMenu = NAV_LINKS.find((l) => l.show !== "all" && isActive(l, pathname))?.show;

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
        const active = isActive(l, pathname);
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
              inMenu ? MORE_ACTIVE[inMenu] : "text-muted hover:bg-surface-2 hover:text-fg"
            }`}
          >
            More
            <svg aria-hidden="true" viewBox="0 0 12 12" className="size-3 fill-current">
              <path d="M2.5 4.5 6 8l3.5-3.5z" />
            </svg>
          </summary>
          <ul className="absolute right-0 z-20 mt-2 w-52 rounded-xl border border-line bg-surface p-1 shadow-lg">
            {NAV_LINKS.map((l) => {
              const active = isActive(l, pathname);
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
