"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useRef } from "react";
import { useAuth } from "@/lib/auth";
import { Icon } from "./Icon";
import { PremiumBadge } from "./PremiumBadge";

/** On phones the header has no link strip, so the links that aren't tabs are in this menu. */
const PHONE_EXTRAS = [
  { href: "/search", label: "Search" },
  { href: "/sources", label: "Library" },
];

const MENU_BOX =
  "absolute right-0 z-20 mt-2 max-h-[calc(100dvh-5rem-var(--tabbar-h))] w-56 overflow-y-auto rounded-xl border border-line bg-surface p-1 shadow-lg";

function MenuList({
  items,
  pathname,
  onPick,
}: {
  items: { href: string; label: string }[];
  pathname: string | null;
  onPick: () => void;
}) {
  return (
    <ul className={MENU_BOX}>
      {items.map((it) => (
        <li key={it.href}>
          <Link
            href={it.href}
            onClick={onPick}
            className="flex min-h-11 items-center rounded-lg px-3 py-2 hover:bg-surface-2"
            aria-current={pathname === it.href ? "page" : undefined}
          >
            {it.label}
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function AccountMenu() {
  const { ready, user, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();
  const ref = useRef<HTMLDetailsElement>(null);

  if (!ready) return <span className="inline-block h-9 w-20" aria-hidden="true" />;

  const close = () => ref.current?.removeAttribute("open");

  if (!user) {
    const next = pathname && !["/signin", "/register", "/forgot-password", "/reset-password"].includes(pathname) ? `?next=${encodeURIComponent(pathname)}` : "";
    return (
      <>
        <Link href={`/signin${next}`} className="btn btn-small btn-primary max-md:hidden">
          Sign in
        </Link>
        {/* Phones: the app's avatar menu, with sign-in first. */}
        <details ref={ref} className="relative md:hidden" key={pathname}>
          <summary className="grid size-11 cursor-pointer list-none place-items-center rounded-full [&::-webkit-details-marker]:hidden">
            <span aria-hidden="true" className="grid size-8 place-items-center rounded-full bg-surface-2 text-muted">
              <Icon name="person" className="size-5" />
            </span>
            <span className="sr-only">Sign in and more</span>
          </summary>
          <MenuList
            pathname={pathname}
            onPick={close}
            items={[
              { href: `/signin${next}`, label: "Sign in" },
              { href: "/register", label: "Create an account" },
              ...PHONE_EXTRAS,
              { href: "/circles", label: "Book circles" },
              { href: "/contribute", label: "Contribute" },
              { href: "/premium", label: "Premium" },
              { href: "/settings", label: "Settings" },
            ]}
          />
        </details>
      </>
    );
  }

  const items: { href: string; label: string; phoneOnly?: boolean }[] = [
    ...PHONE_EXTRAS.map((l) => ({ ...l, phoneOnly: true })),
    ...(user.handle ? [{ href: `/u/${user.handle}`, label: "Your profile" }] : []),
    { href: "/favorites", label: "Favourites" },
    { href: "/following", label: "Following" },
    { href: "/stashes", label: "My collections" },
    { href: "/me/cards", label: "My cards" },
    { href: "/me/earnings", label: "Earnings" },
    { href: "/circles", label: "Book circles" },
    { href: "/review", label: "Review" },
    { href: "/quiz", label: "Quiz" },
    { href: "/contribute", label: "Contribute" },
    { href: "/invite", label: "Invite friends" },
    { href: "/premium", label: user.premium ? "Premium" : "Go Premium" },
    ...(user.role === "moderator"
      ? [
          { href: "/admin", label: "Dashboard" },
          { href: "/moderation", label: "Moderation" },
        ]
      : []),
    { href: "/settings", label: "Settings" },
  ];

  return (
    <details ref={ref} className="relative" key={pathname}>
      <summary className="btn btn-small list-none max-md:size-11 max-md:border-transparent max-md:p-0 [&::-webkit-details-marker]:hidden">
        <span
          aria-hidden="true"
          className="grid size-6 place-items-center rounded-full bg-oxblood text-xs font-bold text-oxblood-fg max-md:size-8 max-md:text-sm"
        >
          {(user.display_name || user.email).slice(0, 1).toUpperCase()}
        </span>
        <span className="hidden max-w-32 truncate lg:inline">{user.display_name || user.email}</span>
        <span className="sr-only lg:hidden">{user.display_name || user.email}</span>
        <span className="sr-only">: account menu</span>
      </summary>
      <div className={MENU_BOX}>
        <p className="truncate px-3 py-2 text-xs text-muted">
          {user.handle ? `@${user.handle} · ` : ""}
          {user.email}
        </p>
        {user.premium ? (
          <p className="px-3 pb-2">
            <PremiumBadge />
          </p>
        ) : null}
        <ul>
          {items.map((it) => (
            <li key={it.href} className={it.phoneOnly ? "md:hidden" : undefined}>
              <Link
                href={it.href}
                onClick={close}
                className="flex min-h-11 items-center rounded-lg px-3 py-2 hover:bg-surface-2"
                aria-current={pathname === it.href ? "page" : undefined}
              >
                {it.label}
              </Link>
            </li>
          ))}
          <li>
            <button
              type="button"
              className="flex min-h-11 w-full items-center rounded-lg px-3 py-2 text-left hover:bg-surface-2"
              onClick={() => {
                close();
                signOut();
                router.push("/");
              }}
            >
              Sign out
            </button>
          </li>
        </ul>
      </div>
    </details>
  );
}
