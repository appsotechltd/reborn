"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/discover", label: "Discover" },
  { href: "/sources", label: "Sources" },
  { href: "/search", label: "Search" },
  { href: "/favorites", label: "Favourites" },
  { href: "/review", label: "Review" },
  { href: "/ask", label: "Ask" },
  { href: "/stashes", label: "Stashes" },
];

export function NavLinks() {
  const pathname = usePathname() ?? "/";
  return (
    <ul className="flex gap-1 overflow-x-auto text-[0.9375rem]">
      {LINKS.map((l) => {
        const active = l.href === "/" ? pathname === "/" : pathname.startsWith(l.href);
        return (
          <li key={l.href} className="shrink-0">
            <Link
              href={l.href}
              aria-current={active ? "page" : undefined}
              className={`inline-flex min-h-10 items-center rounded-full px-3 ${
                active ? "bg-accent-soft font-semibold text-fg" : "text-muted hover:bg-surface-2 hover:text-fg"
              }`}
            >
              {l.label}
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
