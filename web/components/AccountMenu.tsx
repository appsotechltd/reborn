"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useRef } from "react";
import { useAuth } from "@/lib/auth";

export function AccountMenu() {
  const { ready, user, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();
  const ref = useRef<HTMLDetailsElement>(null);

  if (!ready) return <span className="inline-block h-9 w-20" aria-hidden="true" />;

  if (!user) {
    const next = pathname && !["/signin", "/register"].includes(pathname) ? `?next=${encodeURIComponent(pathname)}` : "";
    return (
      <Link href={`/signin${next}`} className="btn btn-small btn-primary">
        Sign in
      </Link>
    );
  }

  const close = () => ref.current?.removeAttribute("open");
  const items: { href: string; label: string }[] = [
    { href: "/stashes", label: "My stashes" },
    { href: "/review", label: "Review" },
    { href: "/quiz", label: "Quiz" },
    { href: "/contribute", label: "Contribute" },
    ...(user.role === "moderator" ? [{ href: "/moderation", label: "Moderation" }] : []),
    { href: "/settings", label: "Settings" },
  ];

  return (
    <details ref={ref} className="relative" key={pathname}>
      <summary className="btn btn-small list-none [&::-webkit-details-marker]:hidden">
        <span
          aria-hidden="true"
          className="grid size-6 place-items-center rounded-full bg-accent text-xs font-bold text-accent-fg"
        >
          {(user.display_name || user.email).slice(0, 1).toUpperCase()}
        </span>
        <span className="max-w-32 truncate">{user.display_name || user.email}</span>
        <span className="sr-only">: account menu</span>
      </summary>
      <div className="absolute right-0 z-20 mt-2 w-56 rounded-xl border border-line bg-surface p-1 shadow-lg">
        <p className="truncate px-3 py-2 text-xs text-muted">{user.email}</p>
        <ul>
          {items.map((it) => (
            <li key={it.href}>
              <Link
                href={it.href}
                onClick={close}
                className="block rounded-lg px-3 py-2 hover:bg-surface-2"
                aria-current={pathname === it.href ? "page" : undefined}
              >
                {it.label}
              </Link>
            </li>
          ))}
          <li>
            <button
              type="button"
              className="block w-full rounded-lg px-3 py-2 text-left hover:bg-surface-2"
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
