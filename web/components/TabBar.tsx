"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon, type IconName } from "./Icon";

/** The app's five tabs, in the app's order, with its icons (outlined, filled when current). */
export const TABS: { href: string; label: string; icon: IconName; activeIcon: IconName; match: string[] }[] = [
  { href: "/", label: "Home", icon: "homeOutlined", activeIcon: "home", match: [] },
  { href: "/discover", label: "Discover", icon: "exploreOutlined", activeIcon: "explore", match: ["/discover"] },
  { href: "/stashes", label: "Collections", icon: "bookmarksOutlined", activeIcon: "bookmarks", match: ["/stashes", "/me"] },
  { href: "/review", label: "Review", icon: "refresh", activeIcon: "refresh", match: ["/review", "/quiz"] },
  { href: "/ask", label: "Ask", icon: "forumOutlined", activeIcon: "forum", match: ["/ask"] },
];

export function isTabActive(tab: (typeof TABS)[number], pathname: string): boolean {
  if (tab.href === "/") return pathname === "/";
  return tab.match.some((m) => pathname === m || pathname.startsWith(`${m}/`));
}

/**
 * Bottom navigation on phones (below md), as in the Flutter app: fixed to the bottom of the
 * screen above the home indicator, the current tab marked with an amber pill. Hidden from md
 * up, where the header's link strip takes over.
 */
export function TabBar() {
  const pathname = usePathname() ?? "/";
  return (
    <nav
      aria-label="Tabs"
      data-tab-bar
      className="fixed inset-x-0 bottom-0 z-10 bg-nav pb-[env(safe-area-inset-bottom,0px)] md:hidden"
    >
      <ul className="mx-auto flex h-[4.25rem] max-w-xl items-stretch">
        {TABS.map((t) => {
          const active = isTabActive(t, pathname);
          return (
            <li key={t.href} className="flex flex-1">
              <Link
                href={t.href}
                aria-current={active ? "page" : undefined}
                className={`flex flex-1 flex-col items-center justify-center gap-1 text-xs focus-visible:outline-offset-[-3px] ${
                  active ? "font-semibold text-accent-text" : "font-medium text-muted hover:text-fg"
                }`}
              >
                <span
                  className={`grid h-8 w-16 place-items-center rounded-full transition-colors ${active ? "bg-accent-soft" : ""}`}
                >
                  <Icon name={active ? t.activeIcon : t.icon} className="size-6" />
                </span>
                {t.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
