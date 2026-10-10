"use client";

import { createContext, useContext, type ReactNode } from "react";

const SiteUrlContext = createContext<string>("");

/** Makes the public site URL (SITE_URL, a server-only setting) available to client components. */
export function SiteUrlProvider({ url, children }: { url: string; children: ReactNode }) {
  return <SiteUrlContext.Provider value={url}>{children}</SiteUrlContext.Provider>;
}

/** Public origin for canonical share and embed links. */
export function useSiteUrl(): string {
  return useContext(SiteUrlContext);
}
