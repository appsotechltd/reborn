// Types mirroring docs/API.md and content/SCHEMA.md exactly.

export type Licence =
  | "public-domain"
  | "us-gov-public-domain"
  | "cc-by-4.0"
  | "cc-by-3.0"
  | "cc-by-sa-4.0"
  | "cc0-1.0"
  | "ogl-3.0"
  | "original-summary";

export type SourceKind =
  | "book"
  | "textbook"
  | "article"
  | "guide"
  | "study"
  | "talk"
  | "podcast"
  | "video";

export interface Quiz {
  question: string;
  options: string[];
  answer: number;
  explanation?: string | null;
}

/** The source as embedded in a Card. */
export interface CardSource {
  id: string;
  title: string;
  authors: string[];
  kind: SourceKind | string;
  url: string;
  licence: Licence | string;
  licence_url: string;
  attribution: string;
}

export interface Card {
  id: string;
  title: string;
  body: string;
  quote?: string | null;
  apply_it: string;
  topic: string;
  tags?: string[] | null;
  locator?: string | null;
  health: boolean;
  disclaimer?: string | null;
  quiz?: Quiz | null;
  source: CardSource;
  credit: string;
}

/** Full source (GET /v1/sources/{id}), fields from content/SCHEMA.md. */
export interface Source extends CardSource {
  publisher?: string | null;
  year?: number | null;
  language?: string | null;
  translator?: string | null;
  retrieved_at?: string | null;
  notes?: string | null;
}

/** Item of GET /v1/sources. */
export interface SourceSummary {
  id: string;
  title: string;
  authors: string[];
  kind: SourceKind | string;
  licence: Licence | string;
  attribution: string;
  topics: string[];
  card_count: number;
  updated_at: string;
}

export interface Topic {
  slug: string;
  name: string;
  card_count: number;
}

export type Role = "member" | "moderator";

export interface User {
  id: string;
  email: string;
  /** Unique, 3-30 of a-z 0-9 _. May be missing from a profile stored before handles existed. */
  handle?: string;
  display_name: string;
  bio?: string;
  role: Role;
  topics: string[];
}

export interface AuthResponse {
  token: string;
  user: User;
}

export interface Stash {
  id: string;
  name: string;
  description: string;
  card_count: number;
  created_at: string;
}

export type ContributionStatus = "pending" | "approved" | "rejected";

export interface ContributionSource {
  title: string;
  authors: string[];
  url: string;
  kind: SourceKind | string;
}

export interface Contribution {
  id: string;
  status: ContributionStatus;
  source: ContributionSource;
  topic: string;
  title: string;
  body: string;
  apply_it: string;
  tags: string[];
  quiz: Quiz | null;
  moderator_note: string | null;
  card_id: string | null;
  created_at: string;
}

export interface NewContribution {
  source: ContributionSource;
  topic: string;
  title: string;
  body: string;
  apply_it: string;
  tags?: string[];
  quiz?: Quiz | null;
}

export type Grade = "again" | "hard" | "good" | "easy";

export interface ReviewItem {
  card: Card;
  due_at: string;
  reps: number;
  interval_days: number;
}

export interface ReviewResult {
  due_at: string;
  interval_days: number;
  reps: number;
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ChatResponse {
  reply: string;
  citations: Card[];
}

export interface FeedResponse {
  cards: Card[];
  next_cursor: string | null;
}

export interface SitemapResponse {
  cards: { id: string; updated_at: string }[];
  sources: { id: string; updated_at: string }[];
  topics: string[];
}

// --- Social layer -----------------------------------------------------------

export type ReactionKind = "like" | "love" | "insightful" | "inspiring" | "helpful";

export interface PostStats {
  reactions: Partial<Record<ReactionKind, number>>;
  comments: number;
  favorites: number;
  shares: number;
  gifts: number;
}

export interface PostViewer {
  reaction: ReactionKind | null;
  favorited: boolean;
  seen: boolean;
}

export type ReasonKind = "source" | "author" | "favorite" | "topic" | "new";

export interface PostReason {
  kind: ReasonKind | string;
  label: string;
}

/** Every published card is a post. `viewer` only when signed in, `reason` only in the timeline. */
export interface Post {
  id: string;
  published_at: string;
  card: Card;
  stats: PostStats;
  viewer?: PostViewer | null;
  reason?: PostReason | null;
}

export interface PostsResponse {
  posts: Post[];
  next_cursor: string | null;
}

export type ShareChannel =
  | "facebook"
  | "x"
  | "whatsapp"
  | "linkedin"
  | "telegram"
  | "email"
  | "instagram"
  | "copy_link"
  | "native"
  | "embed";

export interface PublicUser {
  id: string;
  handle: string;
  display_name: string;
}

export interface Profile extends PublicUser {
  bio: string;
  followers: number;
  following: number;
  favorites: number;
  is_following: boolean;
  is_me: boolean;
}

export interface Comment {
  id: string;
  post_id: string;
  parent_id: string | null;
  body: string;
  author: PublicUser;
  created_at: string;
}

export interface ReportedComment extends Comment {
  status: "visible" | "hidden" | string;
  reports: number;
  reasons: string[] | null;
}

export type FollowKind = "user" | "source" | "author";

export interface FollowState {
  followers: number;
  is_following: boolean;
}

export interface FollowingItem {
  kind: FollowKind;
  target: string;
  label: string;
  handle?: string;
}

export interface AuthorPage extends FollowState {
  name: string;
  sources: SourceSummary[];
}

export interface GiftTier {
  id: string;
  name: string;
  amount_cents: number;
  currency: string;
  product_id: string;
}

export interface GiftTiersResponse {
  tiers: GiftTier[];
  providers: { stripe: boolean; apple: boolean; google: boolean };
}

export interface Gift {
  id: string;
  post_id: string;
  tier: string;
  amount_cents: number;
  currency: string;
  provider: "stripe" | "apple" | "google" | string;
  status: "pending" | "paid" | "refunded" | string;
  created_at: string;
  paid_at: string | null;
}
