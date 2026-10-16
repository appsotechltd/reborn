import Link from "next/link";
import { AccountMenu } from "./AccountMenu";
import { NavLinks } from "./NavLinks";
import { NotificationBell } from "./NotificationBell";
import { HeaderListenButton, StreakChip } from "./StreakChip";
import { ThemeToggle } from "./ThemeToggle";
import { WordmarkR } from "./WordmarkR";

/**
 * The site header. From md up: the wordmark, the link strip, the bell and the account menu.
 * The streak chip (signed in) opens today's idea and the streak. On phones it is the wordmark, the
 * streak, the feed's Listen (on the home feed), the light/dark switch, the bell and the avatar, as in the app; the main links are in the
 * bottom tab bar (easier to reach with a thumb), and the rest are in the avatar menu. The browser's
 * own back button does the app bar's back arrow's job.
 */
export function SiteHeader() {
  return (
    <header
      data-site-header
      className="sticky top-0 z-10 border-b border-line bg-nav/95 backdrop-blur supports-[backdrop-filter]:bg-nav/80 max-md:border-transparent max-md:bg-bg max-md:backdrop-blur-none max-md:supports-[backdrop-filter]:bg-bg"
    >
      <div className="mx-auto flex max-w-5xl items-center gap-x-4 px-4 py-1.5 max-md:gap-x-1 max-md:pl-2 max-md:pr-2 md:py-2">
        <Link
          href="/"
          className="inline-flex min-h-11 items-center px-2 font-serif text-2xl font-semibold tracking-tight max-md:text-[1.6875rem] md:px-0"
          aria-label="Reborn, home"
        >
          <WordmarkR />
          eborn<span className="text-accent-text">.</span>
        </Link>
        <nav aria-label="Main" className="min-w-0 flex-1 max-md:hidden">
          <NavLinks />
        </nav>
        <div className="ml-auto flex items-center gap-1 max-md:gap-0">
          <StreakChip />
          <HeaderListenButton />
          <ThemeToggle />
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
          <Link href="/sources" className="hover:underline">Library</Link>
          <Link href="/authors" className="hover:underline">Authors</Link>
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
