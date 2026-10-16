import type {
  AIConversation,
  AIMessage,
  AIStatus,
  AITopUp,
  AITurnResponse,
  AIWallet,
  AdminStats,
  BlockedUser,
  BlockKind,
  Circle,
  CircleMember,
  CircleMessage,
  DiscoverResponse,
  NotificationsResponse,
  PremiumStatus,
  PublicStash,
  Referrals,
  Streak,
  AuthorPage,
  AuthorSummary,
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
  SummariesResponse,
  SummaryDetail,
  SummaryProgress,
  TimelineResponse,
  Topic,
  User,
  NotifyKind,
  EarningsResponse,
  ImageShape,
  ImageStyle,
  MemberCategory,
  MyPlanResponse,
  NewMemberCard,
  ReportedCard,
  StudioInfo,
  StudioMedia,
  StudioResult,
  UserCardsResponse,
  UserPlanResponse,
  WriterPlan,
  WriterSubscription,
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

/** GET /v1/timeline: `media` keeps only posts with a video or a picture. */
export type TimelineQuery = {
  topics?: string;
  media?: "video" | "image";
  cursor?: string | null;
  limit?: number;
};

export interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  token?: string | null;
  query?: Record<string, string | number | undefined | null>;
  signal?: AbortSignal;
  /**
   * Let the request outlive the page (fetch keepalive), for small fire-and-forget writes
   * sent as the reader leaves: "seen" batches flushed on pagehide, a card view.
   */
  keepalive?: boolean;
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
  if (opts.keepalive) init.keepalive = true;
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
  // Read the body even when it's empty (204): a response left unread is cancelled by the
  // browser, and DevTools and test tools then report a request that succeeded as "aborted".
  const text = await res.text();
  if (res.status === 204 || !text) return undefined as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new ApiError(res.status, "invalid_response", "The server sent a response we couldn't read.");
  }
}

/** POSTs multipart form data (a file upload) and parses the JSON reply. */
export async function uploadRequest<T>(
  baseUrl: string,
  path: string,
  form: FormData,
  token: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  let res: Response;
  try {
    res = await fetchImpl(buildUrl(baseUrl, path), { method: "POST", headers, body: form });
  } catch {
    throw new ApiError(0, "network_error", "Couldn't reach the Reborn server. Check your connection and try again.");
  }
  if (!res.ok) throw await errorFromResponse(res);
  return (await res.json()) as T;
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
    sources: (q: { topic?: string; q?: string; cursor?: string | null; limit?: number } = {}) =>
      req<{ sources: SourceSummary[]; next_cursor: string | null }>("/v1/sources", { query: q }),
    authors: (q: { topic?: string; q?: string; cursor?: string | null; limit?: number } = {}) =>
      req<{ authors: AuthorSummary[]; next_cursor: string | null }>("/v1/authors", { query: q }),
    source: (id: string) =>
      req<{ source: Source; cards: Card[]; follow?: FollowState }>(`/v1/sources/${enc(id)}`),
    search: (q: { q: string; topic?: string; limit?: number }) =>
      req<{ cards: Card[] }>("/v1/search", { query: q }),

    // Auth & account
    register: (body: {
      email: string;
      password: string;
      display_name: string;
      referral_code?: string;
      timezone?: string;
    }) =>
      req<AuthResponse>("/v1/auth/register", { method: "POST", body, token: null }),
    login: (body: { email: string; password: string }) =>
      req<AuthResponse>("/v1/auth/login", { method: "POST", body, token: null }),
    forgotPassword: (email: string) =>
      req<void>("/v1/auth/forgot", { method: "POST", body: { email }, token: null }),
    resetPassword: (body: { token: string; password: string }) =>
      req<AuthResponse>("/v1/auth/reset", { method: "POST", body, token: null }),
    me: () => req<User>("/v1/me"),
    updateMe: (body: {
      display_name?: string;
      handle?: string;
      bio?: string;
      topics?: string[];
      timezone?: string;
      daily_goal?: number;
      notify?: Partial<Record<NotifyKind, boolean>>;
    }) =>
      req<User>("/v1/me", { method: "PATCH", body }),
    deleteMe: () => req<void>("/v1/me", { method: "DELETE" }),
    recordView: (cardId: string) => req<void>(`/v1/cards/${enc(cardId)}/view`, { method: "POST", keepalive: true }),

    // Stashes
    stashes: () => req<{ stashes: Stash[] }>("/v1/stashes"),
    createStash: (body: { name: string; description?: string; is_public?: boolean }) =>
      req<Stash>("/v1/stashes", { method: "POST", body }),
    stash: (id: string) => req<{ stash: Stash; cards: Card[] }>(`/v1/stashes/${enc(id)}`),
    updateStash: (id: string, body: { name?: string; description?: string; is_public?: boolean }) =>
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
    timeline: (q: TimelineQuery = {}, auth = true) =>
      req<PostsResponse>("/v1/timeline", { query: q, token: auth ? getToken() : null }),
    /** The timeline with summary posts woven in (see TimelineItem). */
    timelineWithSummaries: (q: TimelineQuery = {}, auth = true) =>
      req<TimelineResponse>("/v1/timeline", { query: { ...q, with: "summaries" }, token: auth ? getToken() : null }),

    // Full summary posts
    summaries: (q: { kind?: "book" | "topic"; topic?: string; source?: string; cursor?: string | null; limit?: number } = {}) =>
      req<SummariesResponse>("/v1/summaries", { query: q }),
    summary: (id: string) => req<SummaryDetail>(`/v1/summaries/${enc(id)}`),
    setSummaryProgress: (id: string, position: number, finished = false) =>
      req<SummaryProgress>(`/v1/summaries/${enc(id)}/progress`, {
        method: "PUT",
        body: { position, finished },
        keepalive: true,
      }),
    markSeen: (postIds: string[]) =>
      req<void>("/v1/seen", { method: "POST", body: { post_ids: postIds }, keepalive: true }),
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

    // Notifications, streaks, referrals
    notifications: (limit = 50) => req<NotificationsResponse>("/v1/notifications", { query: { limit } }),
    /** Marks the given notifications read, or all of them when ids is omitted. */
    readNotifications: (ids?: string[]) =>
      req<void>("/v1/notifications/read", { method: "POST", body: ids ? { ids } : undefined }),
    registerDevice: (token: string) =>
      req<void>("/v1/devices", { method: "POST", body: { platform: "web", token } }),
    removeDevice: (token: string) => req<void>(`/v1/devices/${enc(token)}`, { method: "DELETE" }),
    streak: () => req<Streak>("/v1/me/streak"),
    referrals: () => req<Referrals>("/v1/me/referrals"),

    // Blocking
    blocks: () => req<{ blocks: BlockedUser[] }>("/v1/me/blocks"),
    setBlock: (userId: string, kind: BlockKind | null) =>
      kind
        ? req<void>(`/v1/blocks/${enc(userId)}`, { method: "PUT", body: { kind } })
        : req<void>(`/v1/blocks/${enc(userId)}`, { method: "DELETE" }),

    // Discover & public stashes
    trending: (q: { topic?: string; days?: number; limit?: number } = {}) =>
      req<{ posts: Post[] }>("/v1/trending", { query: q }),
    discover: () => req<DiscoverResponse>("/v1/discover"),
    userStashes: (handle: string) => req<{ stashes: Stash[] }>(`/v1/users/${enc(handle)}/stashes`),
    publicStash: (id: string) => req<{ stash: PublicStash; cards: Card[] }>(`/v1/public/stashes/${enc(id)}`),

    // Book circles
    circles: (q: { source?: string; mine?: boolean; limit?: number } = {}) =>
      req<{ circles: Circle[] }>("/v1/circles", {
        query: { source: q.source, mine: q.mine ? 1 : undefined, limit: q.limit },
      }),
    createCircle: (body: { source_id: string; name: string; description?: string }) =>
      req<Circle>("/v1/circles", { method: "POST", body }),
    circle: (id: string) => req<Circle>(`/v1/circles/${enc(id)}`),
    joinCircle: (id: string) => req<Circle>(`/v1/circles/${enc(id)}/join`, { method: "POST" }),
    leaveCircle: (id: string) => req<void>(`/v1/circles/${enc(id)}/leave`, { method: "POST" }),
    circleMembers: (id: string) => req<{ members: CircleMember[] }>(`/v1/circles/${enc(id)}/members`),
    circleMessages: (id: string, q: { before?: string; limit?: number } = {}) =>
      req<{ messages: CircleMessage[] }>(`/v1/circles/${enc(id)}/messages`, { query: q }),
    postCircleMessage: (id: string, body: { body: string; post_id?: string }) =>
      req<CircleMessage>(`/v1/circles/${enc(id)}/messages`, { method: "POST", body }),
    deleteCircleMessage: (id: string, msgId: string) =>
      req<void>(`/v1/circles/${enc(id)}/messages/${enc(msgId)}`, { method: "DELETE" }),

    // Premium
    premium: () => req<PremiumStatus>("/v1/premium"),
    premiumCheckout: (plan: string) => req<{ url: string }>("/v1/premium/checkout", { method: "POST", body: { plan } }),
    premiumPortal: () => req<{ url: string }>("/v1/premium/portal", { method: "POST" }),

    // Moderator dashboard
    adminStats: () => req<AdminStats>("/v1/admin/stats"),

    // AI guide
    chat: (messages: ChatMessage[]) =>
      req<ChatResponse>("/v1/agent/chat", { method: "POST", body: { messages } }),

    // Reborn AI (premium)
    aiStatus: () => req<AIStatus>("/v1/ai"),
    aiChat: (message: string, conversationId?: string | null) =>
      req<AITurnResponse>("/v1/ai/chat", {
        method: "POST",
        body: conversationId ? { conversation_id: conversationId, message } : { message },
      }),
    /** Sends a recorded voice message; the server transcribes and answers it. */
    aiVoice: (audio: Blob, filename: string, conversationId?: string | null) => {
      const form = new FormData();
      form.append("audio", audio, filename);
      if (conversationId) form.append("conversation_id", conversationId);
      return uploadRequest<AITurnResponse>(baseUrl, "/v1/ai/voice", form, getToken(), fetchImpl);
    },
    aiSpeech: (messageId: string) =>
      req<{ url: string; units: number; wallet: AIWallet }>(`/v1/ai/messages/${enc(messageId)}/speech`, { method: "POST" }),
    aiConversations: () => req<{ conversations: AIConversation[] }>("/v1/ai/conversations"),
    aiConversation: (id: string) =>
      req<{ conversation: AIConversation; messages: AIMessage[] }>(`/v1/ai/conversations/${enc(id)}`),
    deleteAIConversation: (id: string) => req<void>(`/v1/ai/conversations/${enc(id)}`, { method: "DELETE" }),
    aiUsage: () => req<{ wallet: AIWallet; usage: { kind: string; units: number; created_at: string }[] }>("/v1/ai/usage"),
    topUpCheckout: (pack: string) =>
      req<{ topup_id: string; url: string }>("/v1/ai/topups/checkout", { method: "POST", body: { pack } }),
    topUp: (id: string) => req<AITopUp>(`/v1/ai/topups/${enc(id)}`),

    // Member cards and categories
    myCategories: () => req<{ categories: MemberCategory[] }>("/v1/me/categories"),
    createCategory: (name: string) => req<MemberCategory>("/v1/me/categories", { method: "POST", body: { name } }),
    renameCategory: (id: string, name: string) =>
      req<MemberCategory>(`/v1/me/categories/${enc(id)}`, { method: "PATCH", body: { name } }),
    deleteCategory: (id: string) => req<void>(`/v1/me/categories/${enc(id)}`, { method: "DELETE" }),
    /** `category` is a category id, or "none" for cards without one. */
    myCards: (q: { category?: string; cursor?: string | null; limit?: number } = {}) =>
      req<{ cards: Card[]; next_cursor: string | null }>("/v1/me/cards", { query: q }),
    myCard: (id: string) => req<Card>(`/v1/me/cards/${enc(id)}`),
    createMyCard: (body: NewMemberCard) => req<Card>("/v1/me/cards", { method: "POST", body }),
    updateMyCard: (id: string, body: Partial<NewMemberCard>) =>
      req<Card>(`/v1/me/cards/${enc(id)}`, { method: "PATCH", body }),
    deleteMyCard: (id: string) => req<void>(`/v1/me/cards/${enc(id)}`, { method: "DELETE" }),
    userCards: (handle: string, q: { category?: string; cursor?: string | null; limit?: number } = {}) =>
      req<UserCardsResponse>(`/v1/users/${enc(handle)}/cards`, { query: q }),
    reportPost: (id: string, reason?: string) =>
      req<void>(`/v1/posts/${enc(id)}/report`, { method: "POST", body: reason ? { reason } : {} }),
    reportedCards: () => req<{ cards: ReportedCard[] }>("/v1/moderation/cards"),
    hideCard: (id: string) => req<void>(`/v1/moderation/cards/${enc(id)}/hide`, { method: "POST" }),
    restoreCard: (id: string) => req<void>(`/v1/moderation/cards/${enc(id)}/restore`, { method: "POST" }),

    // The card studio (premium, spends AI units). Each call can take a minute or two.
    studio: () => req<StudioInfo>("/v1/studio"),
    makeCardImage: (id: string, body: { style: ImageStyle; prompt?: string; shape?: ImageShape }) =>
      req<StudioResult>(`/v1/me/cards/${enc(id)}/image`, { method: "POST", body }),
    makeCardAudio: (id: string, voice?: string) =>
      req<StudioResult>(`/v1/me/cards/${enc(id)}/audio`, { method: "POST", body: voice ? { voice } : {} }),
    makeCardVideo: (id: string, voice?: string) =>
      req<StudioResult>(`/v1/me/cards/${enc(id)}/video`, { method: "POST", body: voice ? { voice } : {} }),
    deleteCardMedia: (id: string, kind: StudioMedia) =>
      req<Card>(`/v1/me/cards/${enc(id)}/${kind}`, { method: "DELETE" }),

    // Writer earnings and subscriptions
    earnings: () => req<EarningsResponse>("/v1/me/earnings"),
    myPlan: () => req<MyPlanResponse>("/v1/me/plan"),
    setMyPlan: (body: { tier: string; enabled: boolean; pitch?: string }) =>
      req<WriterPlan>("/v1/me/plan", { method: "PUT", body }),
    userPlan: (handle: string) => req<UserPlanResponse>(`/v1/users/${enc(handle)}/plan`),
    subscribeCheckout: (handle: string) =>
      req<{ url: string }>(`/v1/users/${enc(handle)}/subscribe/checkout`, { method: "POST" }),
    cancelSubscription: (handle: string) =>
      req<WriterSubscription>(`/v1/users/${enc(handle)}/subscription`, { method: "DELETE" }),
    mySubscriptions: () => req<{ subscriptions: WriterSubscription[] }>("/v1/me/subscriptions"),
  };
}

export type ApiClient = ReturnType<typeof createApiClient>;
