import type {
  AuthorPage,
  AuthResponse,
  Card,
  Comment,
  FollowingItem,
  FollowKind,
  FollowState,
  Gift,
  GiftTiersResponse,
  Post,
  PostsResponse,
  Profile,
  PublicUser,
  ReactionKind,
  ReportedComment,
  ShareChannel,
  ChatMessage,
  ChatResponse,
  Contribution,
  FeedResponse,
  Grade,
  NewContribution,
  ReviewItem,
  ReviewResult,
  Source,
  SourceSummary,
  Stash,
  Topic,
  User,
} from "./types";

/**
 * Error thrown for every failed API call. Mirrors the API error shape
 * `{ "error": { "code": "...", "message": "..." } }`.
 * `status` is 0 when the server could not be reached at all.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

export function isApiError(err: unknown): err is ApiError {
  return err instanceof ApiError;
}

const GENERIC_MESSAGES: Record<number, string> = {
  400: "That request wasn't valid.",
  401: "Please sign in to continue.",
  403: "You don't have permission to do that.",
  404: "Not found.",
  409: "That conflicts with something that already exists.",
  429: "Too many requests. Please wait a little and try again.",
  503: "The service is temporarily unavailable.",
};

/** Turn a non-2xx response into an ApiError, tolerating bodies that are not JSON. */
export async function errorFromResponse(res: Response): Promise<ApiError> {
  let code = `http_${res.status}`;
  let message = GENERIC_MESSAGES[res.status] ?? `Request failed (${res.status}).`;
  try {
    const text = await res.text();
    if (text) {
      const data: unknown = JSON.parse(text);
      if (data && typeof data === "object" && "error" in data) {
        const e = (data as { error: unknown }).error;
        if (e && typeof e === "object") {
          const { code: c, message: m } = e as { code?: unknown; message?: unknown };
          if (typeof c === "string" && c) code = c;
          if (typeof m === "string" && m) message = m;
        }
      }
    }
  } catch {
    // Body was not JSON (e.g. a proxy error page); keep the generic message.
  }
  return new ApiError(res.status, code, message);
}

export interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  token?: string | null;
  query?: Record<string, string | number | undefined | null>;
  signal?: AbortSignal;
  /** Next.js fetch extensions (server-side caching). */
  next?: { revalidate?: number | false; tags?: string[] };
  cache?: RequestCache;
  fetchImpl?: typeof fetch;
}

export function buildUrl(
  baseUrl: string,
  path: string,
  query?: RequestOptions["query"],
): string {
  const url = `${baseUrl.replace(/\/+$/, "")}${path}`;
  if (!query) return url;
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query)) {
    if (v !== undefined && v !== null && v !== "") params.set(k, String(v));
  }
  const qs = params.toString();
  return qs ? `${url}?${qs}` : url;
}

/** Low-level JSON request against the Reborn API. Resolves `undefined` for 204. */
export async function apiRequest<T>(
  baseUrl: string,
  path: string,
  opts: RequestOptions = {},
): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;

  const init: RequestInit & { next?: RequestOptions["next"] } = {
    method: opts.method ?? "GET",
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    signal: opts.signal,
  };
  if (opts.cache) init.cache = opts.cache;
  if (opts.next) init.next = opts.next;

  const doFetch = opts.fetchImpl ?? fetch;
  let res: Response;
  try {
    res = await doFetch(buildUrl(baseUrl, path, opts.query), init);
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") throw err;
    throw new ApiError(0, "network_error", "Couldn't reach the Reborn server. Check your connection and try again.");
  }

  if (!res.ok) throw await errorFromResponse(res);
  if (res.status === 204) return undefined as T;
  const text = await res.text();
  if (!text) return undefined as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new ApiError(res.status, "invalid_response", "The server sent a response we couldn't read.");
  }
}

/** Typed client for every endpoint in docs/API.md. */
export function createApiClient(
  baseUrl: string,
  getToken: () => string | null = () => null,
  fetchImpl?: typeof fetch,
) {
  const req = <T,>(path: string, opts: RequestOptions = {}) =>
    apiRequest<T>(baseUrl, path, { token: getToken(), fetchImpl, ...opts });
  const enc = encodeURIComponent;

  return {
    // Library (public)
    topics: () => req<{ topics: Topic[] }>("/v1/topics"),
    feed: (q: { topics?: string; cursor?: string | null; limit?: number } = {}, auth = true) =>
      req<FeedResponse>("/v1/feed", { query: q, token: auth ? getToken() : null }),
    daily: () => req<{ date: string; card: Card }>("/v1/daily"),
    card: (id: string) => req<Card>(`/v1/cards/${enc(id)}`),
    cards: (ids: string[]) => req<{ cards: Card[] }>("/v1/cards", { query: { ids: ids.join(",") } }),
    sources: (q: { topic?: string; cursor?: string | null; limit?: number } = {}) =>
      req<{ sources: SourceSummary[]; next_cursor: string | null }>("/v1/sources", { query: q }),
    source: (id: string) =>
      req<{ source: Source; cards: Card[]; follow?: FollowState }>(`/v1/sources/${enc(id)}`),
    search: (q: { q: string; topic?: string; limit?: number }) =>
      req<{ cards: Card[] }>("/v1/search", { query: q }),

    // Auth & account
    register: (body: { email: string; password: string; display_name: string }) =>
      req<AuthResponse>("/v1/auth/register", { method: "POST", body, token: null }),
    login: (body: { email: string; password: string }) =>
      req<AuthResponse>("/v1/auth/login", { method: "POST", body, token: null }),
    forgotPassword: (email: string) =>
      req<void>("/v1/auth/forgot", { method: "POST", body: { email }, token: null }),
    resetPassword: (body: { token: string; password: string }) =>
      req<AuthResponse>("/v1/auth/reset", { method: "POST", body, token: null }),
    me: () => req<User>("/v1/me"),
    updateMe: (body: { display_name?: string; handle?: string; bio?: string; topics?: string[] }) =>
      req<User>("/v1/me", { method: "PATCH", body }),
    deleteMe: () => req<void>("/v1/me", { method: "DELETE" }),
    recordView: (cardId: string) => req<void>(`/v1/cards/${enc(cardId)}/view`, { method: "POST" }),

    // Stashes
    stashes: () => req<{ stashes: Stash[] }>("/v1/stashes"),
    createStash: (body: { name: string; description?: string }) =>
      req<Stash>("/v1/stashes", { method: "POST", body }),
    stash: (id: string) => req<{ stash: Stash; cards: Card[] }>(`/v1/stashes/${enc(id)}`),
    updateStash: (id: string, body: { name?: string; description?: string }) =>
      req<Stash>(`/v1/stashes/${enc(id)}`, { method: "PATCH", body }),
    deleteStash: (id: string) => req<void>(`/v1/stashes/${enc(id)}`, { method: "DELETE" }),
    addToStash: (id: string, cardId: string) =>
      req<void>(`/v1/stashes/${enc(id)}/cards/${enc(cardId)}`, { method: "PUT" }),
    removeFromStash: (id: string, cardId: string) =>
      req<void>(`/v1/stashes/${enc(id)}/cards/${enc(cardId)}`, { method: "DELETE" }),

    // Review & quiz
    due: (limit = 20) =>
      req<{ items: ReviewItem[]; due_count: number }>("/v1/review/due", { query: { limit } }),
    grade: (cardId: string, grade: Grade) =>
      req<ReviewResult>(`/v1/review/${enc(cardId)}`, { method: "POST", body: { grade } }),
    quiz: (q: { topic?: string; limit?: number } = {}) => req<{ cards: Card[] }>("/v1/quiz", { query: q }),

    // Contributions & moderation
    contribute: (body: NewContribution) =>
      req<Contribution>("/v1/contributions", { method: "POST", body }),
    myContributions: () => req<{ contributions: Contribution[] }>("/v1/contributions/mine"),
    moderationQueue: () => req<{ contributions: Contribution[] }>("/v1/moderation/queue"),
    approve: (id: string, note?: string) =>
      req<Contribution>(`/v1/moderation/${enc(id)}/approve`, {
        method: "POST",
        body: note ? { note } : {},
      }),
    reject: (id: string, note: string) =>
      req<Contribution>(`/v1/moderation/${enc(id)}/reject`, { method: "POST", body: { note } }),

    // Timeline & posts
    timeline: (q: { topics?: string; cursor?: string | null; limit?: number } = {}, auth = true) =>
      req<PostsResponse>("/v1/timeline", { query: q, token: auth ? getToken() : null }),
    markSeen: (postIds: string[]) => req<void>("/v1/seen", { method: "POST", body: { post_ids: postIds } }),
    post: (id: string) => req<Post>(`/v1/posts/${enc(id)}`),
    setFavorite: (id: string, on: boolean) =>
      req<void>(`/v1/posts/${enc(id)}/favorite`, { method: on ? "PUT" : "DELETE" }),
    setReaction: (id: string, kind: ReactionKind | null) =>
      kind
        ? req<void>(`/v1/posts/${enc(id)}/reaction`, { method: "PUT", body: { kind } })
        : req<void>(`/v1/posts/${enc(id)}/reaction`, { method: "DELETE" }),
    share: (id: string, channel: ShareChannel) =>
      req<void>(`/v1/posts/${enc(id)}/share`, { method: "POST", body: { channel } }),

    // Comments
    comments: (postId: string, q: { cursor?: string | null; limit?: number } = {}) =>
      req<{ comments: Comment[]; next_cursor: string | null }>(`/v1/posts/${enc(postId)}/comments`, { query: q }),
    addComment: (postId: string, body: { body: string; parent_id?: string | null }) =>
      req<Comment>(`/v1/posts/${enc(postId)}/comments`, { method: "POST", body }),
    deleteComment: (id: string) => req<void>(`/v1/comments/${enc(id)}`, { method: "DELETE" }),
    reportComment: (id: string, reason?: string) =>
      req<void>(`/v1/comments/${enc(id)}/report`, { method: "POST", body: reason ? { reason } : {} }),

    // People, follows, favourites
    myFavorites: (q: { cursor?: string | null; limit?: number } = {}) =>
      req<PostsResponse>("/v1/me/favorites", { query: q }),
    following: () => req<{ following: FollowingItem[] }>("/v1/me/following"),
    setFollow: (kind: FollowKind, target: string, on: boolean) =>
      req<FollowState>(`/v1/follows/${kind}/${enc(target)}`, { method: on ? "PUT" : "DELETE" }),
    profile: (handle: string) => req<Profile>(`/v1/users/${enc(handle)}`),
    userFavorites: (handle: string, q: { cursor?: string | null; limit?: number } = {}) =>
      req<PostsResponse>(`/v1/users/${enc(handle)}/favorites`, { query: q }),
    userFollowers: (handle: string, q: { cursor?: string | null; limit?: number } = {}) =>
      req<{ users: PublicUser[]; next_cursor: string | null }>(`/v1/users/${enc(handle)}/followers`, { query: q }),
    author: (name: string) => req<AuthorPage>(`/v1/authors/${enc(name)}`),

    // Gifts
    giftTiers: () => req<GiftTiersResponse>("/v1/gifts/tiers"),
    giftCheckout: (postId: string, tier: string) =>
      req<{ gift_id: string; url: string }>(`/v1/posts/${enc(postId)}/gifts/checkout`, { method: "POST", body: { tier } }),
    gift: (id: string) => req<Gift>(`/v1/gifts/${enc(id)}`),

    // Comment moderation
    reportedComments: () => req<{ comments: ReportedComment[] }>("/v1/moderation/comments"),
    hideComment: (id: string) => req<void>(`/v1/moderation/comments/${enc(id)}/hide`, { method: "POST" }),
    restoreComment: (id: string) => req<void>(`/v1/moderation/comments/${enc(id)}/restore`, { method: "POST" }),

    // AI guide
    chat: (messages: ChatMessage[]) =>
      req<ChatResponse>("/v1/agent/chat", { method: "POST", body: { messages } }),
  };
}

export type ApiClient = ReturnType<typeof createApiClient>;
