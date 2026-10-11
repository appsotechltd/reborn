import Link from "next/link";
import { AccountMenu } from "./AccountMenu";
import { NavLinks } from "./NavLinks";
import { NotificationBell } from "./NotificationBell";

export function SiteHeader() {
  return (
    <header data-site-header className="border-b border-line bg-nav/95 backdrop-blur supports-[backdrop-filter]:bg-nav/80 sticky top-0 z-10">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center gap-x-4 gap-y-0.5 px-4 py-1.5 md:flex-nowrap md:py-2">
        <Link
          href="/"
          className="inline-flex min-h-11 items-center font-serif text-2xl font-semibold tracking-tight"
          aria-label="Reborn, home"
        >
          Reborn<span className="text-accent-text">.</span>
        </Link>
        <nav aria-label="Main" className="order-3 -mx-1 w-full min-w-0 md:order-none md:mx-0 md:w-auto md:flex-1">
          <NavLinks />
        </nav>
        <div className="ml-auto flex items-center gap-1">
          <NotificationBell />
          <AccountMenu />
        </div>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer data-site-footer className="mt-16 border-t border-line">
      <div className="mx-auto max-w-5xl px-4 py-8 text-sm text-muted">
        <p>
          <strong className="text-fg">Reborn</strong> turns ideas from books and open sources into one-minute idea
          cards. Every card credits its source and licence.
        </p>
        <p className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
          <Link href="/sources" className="hover:underline">All sources</Link>
          <Link href="/search" className="hover:underline">Search</Link>
          <Link href="/contribute" className="hover:underline">Contribute an idea</Link>
          <Link href="/ask" className="hover:underline">Ask the guide</Link>
          <Link href="/discover" className="hover:underline">Discover</Link>
          <Link href="/circles" className="hover:underline">Book circles</Link>
          <Link href="/premium" className="hover:underline">Premium</Link>
        </p>
      </div>
    </footer>
  );
}
