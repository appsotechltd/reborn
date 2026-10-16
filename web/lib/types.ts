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

/** The card read aloud in its book's voice (content/audio). Absent until it has been recorded. */
export interface CardAudio {
  /** Absolute, or a path relative to the API base URL (as explainer URLs are). */
  url: string;
  duration_s: number;
  voice: string;
  /** The voice's display name, e.g. "George". */
  voice_name: string;
}

/** The card's picture (content/images): a 3:2 illustration, 3D render or chart. Absent on text-only cards. */
export interface CardImage {
  /** Absolute, or a path relative to the API base URL (as explainer URLs are). */
  url: string;
  full_url?: string | null;
  type: "illustration" | "3d" | "chart" | string;
  caption: string;
  /** Charts only: "data" when drawn from real figures, "illustration" when it shows a concept. */
  basis?: string | null;
  source?: string | null;
  credit?: string | null;
}

/** The card's image post: a designed 4:5 picture with the title set over a painted scene, shown in the feed. */
export interface PostImage {
  /** Absolute, or a path relative to the API base URL. */
  url: string;
  width: number;
  height: number;
  alt: string;
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
  audio?: CardAudio | null;
  image?: CardImage | null;
  post_image?: PostImage | null;
  // Member cards (written by a member, not from a book) add these:
  /** The member who wrote it. Present only on member cards. */
  author?: PublicUser | null;
  category?: MemberCategory | null;
  /** Who can see it: an Audience, or "hidden" when reports or a moderator took it down. */
  visibility?: Audience | "hidden" | string;
  created_at?: string;
  /** An illustrated video made in the card studio. */
  video?: CardVideo | null;
}

// --- Member cards, the card studio, writer earnings and subscriptions -----------

export type Audience = "everyone" | "followers" | "subscribers" | "private";

export interface MemberCategory {
  id: string;
  name: string;
  /** Present in category lists. */
  card_count?: number;
}

/** One illustration of an illustrated video, shown for an equal share of the narration. */
export interface VideoScene {
  url: string;
  width: number;
  height: number;
}

export interface CardVideo {
  kind: "illustrated" | string;
  scenes: VideoScene[];
  audio_url: string;
  voice: string;
  duration_s: number;
}

export type ImageStyle = "sketch" | "illustration" | "picture";
export type ImageShape = "landscape" | "square" | "portrait";
export type StudioMedia = "image" | "audio" | "video";

export interface StudioRate {
  kind: ImageStyle | "audio" | "video" | string;
  units: number;
  per: string;
}

/** GET /v1/studio. */
export interface StudioInfo {
  available: boolean;
  rates: StudioRate[];
  video_scenes: number;
  voices: { id: string; name: string }[];
  audiences: Audience[];
  monthly_units: number;
  premium: boolean;
  wallet: AIWallet | null;
}

export interface StudioResult {
  card: Card;
  units: number;
  wallet: AIWallet;
}

export interface NewMemberCard {
  title: string;
  body: string;
  apply_it?: string;
  topic: string;
  /** "" clears it on update. */
  category_id?: string;
  audience?: Audience;
}

export interface ReportedCard {
  card: Card;
  status: string;
  reports: number;
  reasons: string[] | null;
}

export interface EarningItem {
  kind: "gift" | "subscription" | string;
  /** Gifts only ("" for subscriptions). */
  post_id?: string | null;
  post_title?: string | null;
  tier: string;
  amount_cents: number;
  author_cents: number;
  currency: string;
  /** Who paid, or null when their account is gone. */
  from: PublicUser | null;
  paid_at: string;
}

export interface EarningsResponse {
  earnings: {
    total_cents: number;
    this_month_cents: number;
    gifts: number;
    subscribers: number;
    currency: string;
    recent: EarningItem[] | null;
  };
  commission_percent: number;
  store_fee_percent: number;
}

export interface WriterTier {
  id: string;
  amount_cents: number;
  currency: string;
  product_id: string;
}

export interface WriterPlan {
  tier: string;
  enabled: boolean;
  pitch: string;
  subscribers: number;
  updated_at: string;
}

export interface MyPlanResponse {
  plan: WriterPlan | null;
  tiers: WriterTier[];
  commission_percent: number;
  store_fee_percent: number;
}

export interface WriterSubscription {
  writer: PublicUser;
  tier: string;
  provider: string;
  /** False once a web subscription is cancelled (or for app passes): it ends at expires_at. */
  renews: boolean;
  expires_at: string;
  active: boolean;
}

/** GET /v1/users/{handle}/plan. `plan` is null when the writer doesn't sell subscriptions. */
export interface UserPlanResponse {
  plan: { pitch: string; subscribers: number } | null;
  tier: WriterTier | null;
  locked_cards: number;
  subscription: WriterSubscription | null;
  providers: { stripe: boolean; apple: boolean; google: boolean };
}

export interface UserCardsResponse extends PostsResponse {
  /** First page only: the writer's categories that hold cards the viewer may see. */
  categories?: MemberCategory[];
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
  /** Cards with an explainer video. */
  video_count?: number;
  updated_at: string;
}

/** Item of GET /v1/authors. */
export interface AuthorSummary {
  name: string;
  /** How many works. */
  sources: number;
  card_count: number;
  video_count: number;
  topics: string[];
  followers: number;
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
  /** IANA timezone, e.g. "Europe/London". */
  timezone?: string;
  /** Ideas a day, 1-50. */
  daily_goal?: number;
  notify?: Partial<Record<NotifyKind, boolean>>;
  referral_code?: string;
  premium?: boolean;
  premium_until?: string | null;
}

export type NotifyKind = "daily" | "replies" | "follows" | "circles";

export interface AuthResponse {
  token: string;
  user: User;
}

export interface Stash {
  id: string;
  name: string;
  description: string;
  card_count: number;
  /** Public stashes show on the owner's profile and at /s/{id}. */
  is_public?: boolean;
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
  /** Absent from APIs older than summary posts. */
  summaries?: { id: string; updated_at: string }[];
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

export type ReasonKind = "source" | "author" | "favorite" | "topic" | "writer" | "new";

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

// --- Full summary posts -------------------------------------------------------

/**
 * "full": a public-domain or openly licensed book, every idea in order. "key-ideas": an
 * in-copyright book's key ideas in our own words. "topic": hand-picked parts from several books.
 */
export type SummaryCoverage = "full" | "key-ideas" | "guide" | "topic";

/** Where the signed-in reader is in a summary. `position` is the zero-based part. */
export interface SummaryProgress {
  started: boolean;
  position: number;
  finished: boolean;
}

/** One post for a whole book or topic, read part by part; every part is a card. */
export interface Summary {
  id: string;
  kind: "book" | "topic";
  title: string;
  description: string;
  topic: string;
  topic_name: string;
  coverage: SummaryCoverage | string;
  /** The book, for book summaries. */
  source?: CardSource | null;
  authors: string[];
  source_count: number;
  part_count: number;
  minutes: number;
  published_at: string;
  viewer?: SummaryProgress | null;
  /** A guide's cover picture, when it has one. */
  cover?: CardImage | null;
}

/** GET /v1/summaries/{id}: the summary with its parts in reading order. */
export interface SummaryDetail extends Summary {
  parts: Card[];
}

export interface SummariesResponse {
  summaries: Summary[];
  next_cursor: string | null;
}

/** A summary post in the timeline (only with ?with=summaries). */
export interface SummaryItem {
  id: string;
  kind: "summary";
  summary: Summary;
}

export type TimelineItem = Post | SummaryItem;

export interface TimelineResponse {
  posts: TimelineItem[];
  next_cursor: string | null;
}

export function isSummaryItem(item: TimelineItem): item is SummaryItem {
  return (item as SummaryItem).kind === "summary";
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
  /** Every published card by the author, ordered by book then card. */
  cards?: Card[];
  card_count?: number;
  video_count?: number;
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

// --- Engagement: notifications, streaks, referrals, blocks, discover, circles, premium, admin ---

export type NotificationKind = "daily" | "reply" | "follow" | "circle" | "reward";

export interface AppNotification {
  id: string;
  kind: NotificationKind | string;
  text: string;
  actor: PublicUser | null;
  post_id: string | null;
  comment_id: string | null;
  circle_id: string | null;
  read_at: string | null;
  created_at: string;
}

export interface NotificationsResponse {
  notifications: AppNotification[];
  unread: number;
}

export interface Streak {
  current: number;
  longest: number;
  goal: number;
  today: number;
  goal_met: boolean;
  last_days: { day: string; ideas: number }[];
}

export interface Referrals {
  code: string;
  link: string;
  invited: number;
  rewarded: number;
  reward_days: number;
}

export type BlockKind = "block" | "mute";

export interface BlockedUser extends PublicUser {
  kind: BlockKind;
}

export interface PopularSource extends SourceSummary {
  followers: number;
}

export interface PopularAuthor {
  name: string;
  followers: number;
  sources: number;
}

export interface Circle {
  id: string;
  name: string;
  description: string;
  source: { id: string; title: string };
  owner: PublicUser | null;
  members: number;
  is_member: boolean;
  role: "owner" | "member" | null;
  created_at: string;
}

export interface CircleMember extends PublicUser {
  role: "owner" | "member" | string;
  joined_at: string;
}

export interface CircleMessage {
  id: string;
  circle_id: string;
  body: string;
  post_id: string | null;
  author: PublicUser;
  created_at: string;
}

export interface DiscoverResponse {
  trending: Post[];
  new: Post[];
  books: PopularSource[];
  authors: PopularAuthor[];
  circles: Circle[];
}

export interface PublicStash extends Stash {
  owner: PublicUser;
}

export interface PremiumPlan {
  id: "monthly" | "yearly" | string;
  name: string;
  amount_cents: number;
  currency: string;
  interval: string;
  product_id: string;
}

export interface PremiumStatus {
  plans: PremiumPlan[];
  providers: { stripe: boolean; apple: boolean; google: boolean };
  premium: boolean;
  premium_until: string | null;
  subscription: { provider: string; plan: string; status: string; expires_at: string } | null;
}

export interface AdminStats {
  users: { total: number; new_7d: number; new_30d: number; dau: number; wau: number; mau: number; premium: number };
  retention: { cohort: number; d1: number; d7: number };
  engagement: { ideas_read_7d: number; reactions_7d: number; comments_7d: number; favorites_7d: number; shares_7d: number };
  revenue: {
    gifts_30d: { provider: string; currency: string; amount_cents: number; count: number }[] | null;
    subscriptions: { provider: string; count: number }[] | null;
  };
  moderation: { pending_contributions: number; reported_comments: number };
  content: { posts: number; sources: number };
  daily: { day: string; signups: number; active: number }[] | null;
  top_posts: { id: string; title: string; score: number }[] | null;
}

// --- Reborn AI -----------------------------------------------------------------

export type AIKind = "text" | "chart" | "voice" | "sketch" | "illustration" | "picture";

export interface AIWallet {
  monthly_units: number;
  allowance_used: number;
  allowance_left: number;
  topup_units: number;
  remaining: number;
  resets_at: string;
}

export interface AIRate {
  kind: AIKind;
  units: number;
  per: string;
}

export interface UnitPack {
  id: string;
  name: string;
  units: number;
  amount_cents: number;
  currency: string;
  product_id: string;
}

export interface AIStatus {
  available: boolean;
  premium: boolean;
  wallet: AIWallet | null;
  rates: AIRate[];
  packs: UnitPack[];
  providers: { stripe: boolean; apple: boolean; google: boolean };
}

export interface AIChart {
  kind: "bar" | "line" | "pie";
  title: string;
  unit?: string;
  labels: string[];
  series: { name: string; values: number[] }[];
}

export type AIAttachment =
  | { type: "image"; style: "sketch" | "illustration" | "picture"; url: string; alt: string; width: number; height: number }
  | { type: "chart"; alt: string; chart: AIChart };

export interface AIMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  voice: boolean;
  citations: Card[];
  attachments: AIAttachment[];
  units: number;
  created_at: string;
}

export interface AIConversation {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
}

export interface AITurnResponse {
  conversation: AIConversation;
  user_message: AIMessage;
  message: AIMessage;
  wallet: AIWallet;
  transcript?: string;
}

export interface AITopUp {
  id: string;
  pack: string;
  units: number;
  amount_cents: number;
  currency: string;
  provider: string;
  status: "pending" | "paid" | "refunded";
  created_at: string;
  paid_at: string | null;
}
