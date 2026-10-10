import type {
  AuthResponse,
  Card,
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
    source: (id: string) => req<{ source: Source; cards: Card[] }>(`/v1/sources/${enc(id)}`),
    search: (q: { q: string; topic?: string; limit?: number }) =>
      req<{ cards: Card[] }>("/v1/search", { query: q }),

    // Auth & account
    register: (body: { email: string; password: string; display_name: string }) =>
      req<AuthResponse>("/v1/auth/register", { method: "POST", body, token: null }),
    login: (body: { email: string; password: string }) =>
      req<AuthResponse>("/v1/auth/login", { method: "POST", body, token: null }),
    me: () => req<User>("/v1/me"),
    updateMe: (body: { display_name?: string; topics?: string[] }) =>
      req<User>("/v1/me", { method: "PATCH", body }),
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

    // AI guide
    chat: (messages: ChatMessage[]) =>
      req<ChatResponse>("/v1/agent/chat", { method: "POST", body: { messages } }),
  };
}

export type ApiClient = ReturnType<typeof createApiClient>;
