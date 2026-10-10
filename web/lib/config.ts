const DEFAULT_API = "http://localhost:8080";
const DEFAULT_SITE = "http://localhost:3000";

function trimSlash(url: string): string {
  return url.replace(/\/+$/, "");
}

/** API base for server-side fetches (server components, sitemap). */
export function serverApiUrl(): string {
  return trimSlash(process.env.API_URL || process.env.NEXT_PUBLIC_API_URL || DEFAULT_API);
}

/** API base for browser fetches. NEXT_PUBLIC_* is inlined at build time. */
export function browserApiUrl(): string {
  return trimSlash(process.env.NEXT_PUBLIC_API_URL || DEFAULT_API);
}

/** Public URL of this site, for canonical links, Open Graph, sitemap and robots. */
export function siteUrl(): string {
  return trimSlash(process.env.SITE_URL || DEFAULT_SITE);
}

export const SITE_NAME = "Reborn";
export const SITE_TAGLINE = "Big ideas from great books, one minute at a time.";

/** Public pages are regenerated at most this often (seconds). */
export const REVALIDATE_SECONDS = 600;
