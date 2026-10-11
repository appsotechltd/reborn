import { connection } from "next/server";
import { apiRequest, isApiError, type RequestOptions } from "./api";
import { REVALIDATE_SECONDS, serverApiUrl } from "./config";
import type {
  Circle,
  DiscoverResponse,
  PublicStash,
  AuthorPage,
  AuthorSummary,
  Card,
  FeedResponse,
  FollowState,
  Post,
  PostsResponse,
  Profile,
  Source,
  SourceSummary,
  SitemapResponse,
  Topic,
} from "./types";

// Server-side, anonymous, cached reads of the public library. Every fetch is
// cached by Next.js for REVALIDATE_SECONDS and deduplicated within a render, so
// generateMetadata and the page share a single request.

function get<T>(path: string, query?: RequestOptions["query"]): Promise<T> {
  return apiRequest<T>(serverApiUrl(), path, {
    query,
    next: { revalidate: REVALIDATE_SECONDS },
  });
}

/** Returns null for 404 so pages can call notFound(). Other errors propagate. */
async function orNull<T>(p: Promise<T>): Promise<T | null> {
  try {
    return await p;
  } catch (err) {
    if (isApiError(err) && err.status === 404) return null;
    throw err;
  }
}

export const getCard = (id: string) => orNull(get<Card>(`/v1/cards/${encodeURIComponent(id)}`));
export const getSource = (id: string) =>
  orNull(get<{ source: Source; cards: Card[]; follow?: FollowState }>(`/v1/sources/${encodeURIComponent(id)}`));
export const getPost = (id: string) => orNull(get<Post>(`/v1/posts/${encodeURIComponent(id)}`));
/** The anonymous timeline (everything, newest first), as seen by signed-out visitors and crawlers. */
export const getTimeline = (limit = 10) => get<PostsResponse>("/v1/timeline", { limit });
export const getAuthor = (name: string) => orNull(get<AuthorPage>(`/v1/authors/${encodeURIComponent(name)}`));
export const getDiscover = () => get<DiscoverResponse>("/v1/discover");
export const getPublicStash = (id: string) =>
  orNull(get<{ stash: PublicStash; cards: Card[] }>(`/v1/public/stashes/${encodeURIComponent(id)}`));
export const getProfile = (handle: string) => orNull(get<Profile>(`/v1/users/${encodeURIComponent(handle)}`));
/** Whether a book circle exists (circles are public; membership is checked by the page in the browser). */
export const getCircle = (id: string) => orNull(get<Circle>(`/v1/circles/${encodeURIComponent(id)}`));
export const getTopics = () => get<{ topics: Topic[] }>("/v1/topics").then((r) => r.topics);
export const getDaily = () => get<{ date: string; card: Card }>("/v1/daily");
export const getFeed = (q: { topics?: string; cursor?: string; limit?: number } = {}) =>
  get<FeedResponse>("/v1/feed", q);
export const getSitemap = () => get<SitemapResponse>("/v1/sitemap");

/** All sources (follows cursors, capped to keep a single page reasonable). */
export async function getAllSources(topic?: string, max = 500): Promise<SourceSummary[]> {
  const out: SourceSummary[] = [];
  let cursor: string | null = null;
  do {
    const page: { sources: SourceSummary[]; next_cursor: string | null } = await get(
      "/v1/sources",
      { topic, cursor, limit: 50 },
    );
    out.push(...page.sources);
    cursor = page.next_cursor;
  } while (cursor && out.length < max);
  return out;
}

export interface LibraryQuery {
  topic?: string;
  q?: string;
  cursor?: string | null;
  limit?: number;
}

/** One page of GET /v1/sources (the Library's Books tab). */
export const getSourcesPage = (q: LibraryQuery = {}) =>
  get<{ sources: SourceSummary[]; next_cursor: string | null }>("/v1/sources", { limit: 50, ...q });

/** One page of GET /v1/authors (the Library's Authors tab). */
export const getAuthorsPage = (q: LibraryQuery = {}) =>
  get<{ authors: AuthorSummary[]; next_cursor: string | null }>("/v1/authors", { limit: 50, ...q });

/** Every author (follows cursors, capped), for the sitemap. */
export async function getAllAuthors(max = 2000): Promise<AuthorSummary[]> {
  const out: AuthorSummary[] = [];
  let cursor: string | null = null;
  do {
    const page: { authors: AuthorSummary[]; next_cursor: string | null } = await getAuthorsPage({ cursor });
    out.push(...page.authors);
    cursor = page.next_cursor;
  } while (cursor && out.length < max);
  return out;
}

/** Search is per-query and not worth caching long. */
export function searchCards(q: string, topic?: string, limit = 20) {
  return apiRequest<{ cards: Card[] }>(serverApiUrl(), "/v1/search", {
    query: { q, topic, limit },
    cache: "no-store",
  }).then((r) => r.cards);
}

/**
 * Loads data for a public page, falling back gracefully when the API is down
 * (network error or 5xx). On failure the render opts out of static caching via
 * `connection()`: at build time the route becomes dynamic instead of failing or
 * baking an outage into the static output, and at runtime a background
 * revalidation keeps serving the last good page.
 */
export async function loadOr<T>(
  load: () => Promise<T>,
  fallback: T,
): Promise<{ data: T; ok: boolean }> {
  try {
    return { data: await load(), ok: true };
  } catch (err) {
    const unavailable = !isApiError(err) || err.status === 0 || err.status >= 500;
    if (!unavailable) throw err;
    if (process.env.NEXT_PHASE !== "phase-production-build") console.warn(`[reborn] API unavailable: ${err instanceof Error ? err.message : String(err)}`);
  }
  await connection();
  return { data: fallback, ok: false };
}
