"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useRef } from "react";
import { useAuth } from "@/lib/auth";
import { PremiumBadge } from "./PremiumBadge";

export function AccountMenu() {
  const { ready, user, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();
  const ref = useRef<HTMLDetailsElement>(null);

  if (!ready) return <span className="inline-block h-9 w-20" aria-hidden="true" />;

  if (!user) {
    const next = pathname && !["/signin", "/register", "/forgot-password", "/reset-password"].includes(pathname) ? `?next=${encodeURIComponent(pathname)}` : "";
    return (
      <Link href={`/signin${next}`} className="btn btn-small btn-primary">
        Sign in
      </Link>
    );
  }

  const close = () => ref.current?.removeAttribute("open");
  const items: { href: string; label: string }[] = [
    ...(user.handle ? [{ href: `/u/${user.handle}`, label: "Your profile" }] : []),
    { href: "/favorites", label: "Favourites" },
    { href: "/following", label: "Following" },
    { href: "/stashes", label: "My stashes" },
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
      <summary className="btn btn-small list-none [&::-webkit-details-marker]:hidden">
        <span
          aria-hidden="true"
          className="grid size-6 place-items-center rounded-full bg-oxblood text-xs font-bold text-oxblood-fg"
        >
          {(user.display_name || user.email).slice(0, 1).toUpperCase()}
        </span>
        <span className="hidden max-w-32 truncate lg:inline">{user.display_name || user.email}</span>
        <span className="sr-only lg:hidden">{user.display_name || user.email}</span>
        <span className="sr-only">: account menu</span>
      </summary>
      <div className="absolute right-0 z-20 mt-2 w-56 rounded-xl border border-line bg-surface p-1 shadow-lg">
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
            <li key={it.href}>
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
