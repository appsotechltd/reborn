import Link from "next/link";
import { AccountMenu } from "./AccountMenu";
import { NavLinks } from "./NavLinks";

export function SiteHeader() {
  return (
    <header className="border-b border-line bg-bg/95 backdrop-blur supports-[backdrop-filter]:bg-bg/80 sticky top-0 z-10">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2 sm:flex-nowrap">
        <Link href="/" className="font-serif text-2xl font-semibold tracking-tight" aria-label="Reborn, home">
          Reborn<span className="text-accent">.</span>
        </Link>
        <nav aria-label="Main" className="order-3 w-full min-w-0 sm:order-none sm:w-auto sm:flex-1">
          <NavLinks />
        </nav>
        <div className="ml-auto">
          <AccountMenu />
        </div>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="mt-16 border-t border-line">
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
        </p>
      </div>
    </footer>
  );
}
