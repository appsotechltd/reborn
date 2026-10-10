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

/** An explainer video rendered for a card (see content/explainers). */
export interface Explainer {
  kind: "animated" | "film" | string;
  /** Absolute, or a path relative to the API base URL. */
  video_url: string;
  poster_url: string;
  captions_url?: string | null;
  duration_s: number;
  width: number;
  height: number;
  narrated: boolean;
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
  explainer?: Explainer | null;
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
  display_name: string;
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
