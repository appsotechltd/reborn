"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { TabBar } from "./TabBar";

/**
 * Wraps pages in the site header and footer (and, on phones, the app's bottom tab bar), except embeds (/embed/*), which
 * render bare so they fit inside an iframe on someone else's site.
 */
export function SiteChrome({ header, footer, children }: { header: ReactNode; footer: ReactNode; children: ReactNode }) {
  const pathname = usePathname() ?? "/";
  if (pathname.startsWith("/embed/")) {
    return (
      <main id="main" className="w-full">
        {children}
      </main>
    );
  }
  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-4 focus:py-2"
      >
        Skip to content
      </a>
      {header}
      <main id="main" className="mx-auto w-full max-w-5xl flex-1 px-4 py-8 max-md:pt-4 sm:py-12">
        {children}
      </main>
      {footer}
      <TabBar />
    </>
  );
}
