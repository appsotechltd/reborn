import { formatMoney } from "./social";
import type { AppNotification, PremiumStatus } from "./types";

// --- Notifications -----------------------------------------------------------

/** Where a notification leads: its comment, post, circle or the person who acted. */
export function notificationHref(n: AppNotification): string {
  if (n.circle_id) return `/circles/${n.circle_id}`;
  if (n.post_id) return `/ideas/${n.post_id}${n.comment_id ? `#comment-${n.comment_id}` : ""}`;
  if (n.kind === "follow" && n.actor) return `/u/${n.actor.handle}`;
  if (n.kind === "reward") return "/premium";
  if (n.actor) return `/u/${n.actor.handle}`;
  return "/notifications";
}

/** Marks the given ids read (or all, when ids is omitted) and recounts unread. */
export function markNotificationsRead(
  list: AppNotification[],
  ids?: string[],
  now = new Date().toISOString(),
): { notifications: AppNotification[]; unread: number } {
  const which = ids ? new Set(ids) : null;
  const notifications = list.map((n) => (!n.read_at && (!which || which.has(n.id)) ? { ...n, read_at: now } : n));
  return { notifications, unread: notifications.filter((n) => !n.read_at).length };
}

/** Tells the header bell to refresh its unread count (after reading in the inbox). */
export const NOTIFICATIONS_CHANGED = "reborn:notifications-changed";

export function announceNotificationsChanged() {
  if (typeof window !== "undefined") window.dispatchEvent(new Event(NOTIFICATIONS_CHANGED));
}

// --- Referrals ---------------------------------------------------------------

const REFERRAL_KEY = "reborn.referral";
const REFERRAL_RE = /^[A-Za-z0-9_-]{4,40}$/;

export function isReferralCode(code: string | null | undefined): code is string {
  return !!code && REFERRAL_RE.test(code);
}

/** Remembers a referral code from /join?ref= until sign-up. */
export function saveReferral(code: string): void {
  if (!isReferralCode(code)) return;
  try {
    window.localStorage.setItem(REFERRAL_KEY, code);
  } catch {
    // Storage unavailable: the code still travels in the /register?ref= link.
  }
}

export function readReferral(): string | null {
  try {
    const v = window.localStorage.getItem(REFERRAL_KEY);
    return isReferralCode(v) ? v : null;
  } catch {
    return null;
  }
}

export function clearReferral(): void {
  try {
    window.localStorage.removeItem(REFERRAL_KEY);
  } catch {
    // ignore
  }
}

// --- Time ---------------------------------------------------------------------

/** The browser's IANA timezone, e.g. "Europe/London". */
export function browserTimezone(): string | undefined {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || undefined;
  } catch {
    return undefined;
  }
}

export function timezones(): string[] {
  try {
    const fn = (Intl as unknown as { supportedValuesOf?: (k: string) => string[] }).supportedValuesOf;
    if (fn) return fn("timeZone");
  } catch {
    // fall through
  }
  return [];
}

/**
 * Today's progress line on the streak card. Before the goal: "2 of 3 ideas today".
 * Once it is met, the count can pass the goal, so it no longer reads "of":
 * "Goal met · 21 ideas today (goal 3)".
 */
export function streakTodayText(s: { today: number; goal: number; goal_met?: boolean }): string {
  const ideas = (n: number) => `${n} ${n === 1 ? "idea" : "ideas"}`;
  if (s.goal_met || s.today >= s.goal) return `Goal met · ${ideas(s.today)} today (goal ${s.goal})`;
  return `${s.today} of ${ideas(s.goal)} today`;
}

/** Short weekday for a YYYY-MM-DD day, without timezone surprises. */
export function weekday(day: string): string {
  const [y, m, d] = day.split("-").map(Number);
  if (!y || !m || !d) return day;
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString("en", { weekday: "short", timeZone: "UTC" });
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en", { day: "numeric", month: "short", year: "numeric" });
}

// --- Premium ------------------------------------------------------------------

/** One-line summary of the viewer's premium status. */
export function premiumSummary(s: Pick<PremiumStatus, "premium" | "premium_until" | "subscription">): string {
  if (!s.premium) return "You're on the free plan.";
  const sub = s.subscription;
  const until = s.premium_until ? formatDate(s.premium_until) : null;
  if (sub && sub.status === "active") {
    const plan = sub.plan === "yearly" ? "yearly" : sub.plan === "monthly" ? "monthly" : sub.plan;
    return `You're a Premium member (${plan}${until ? `, renews ${until}` : ""}).`;
  }
  if (sub) return `You're a Premium member until ${until ?? formatDate(sub.expires_at)}. Your plan won't renew.`;
  return until ? `You have Premium until ${until}.` : "You're a Premium member.";
}

export function planPrice(p: { amount_cents: number; currency: string; interval: string }): string {
  return `${formatMoney(p.amount_cents, p.currency)} / ${p.interval === "year" || p.interval === "yearly" ? "year" : "month"}`;
}

// --- Circles ------------------------------------------------------------------

/**
 * Merges fetched circle messages into what is shown: no duplicates, oldest first.
 * With `replaceFrom`, shown messages at or after that time that the server no
 * longer returns (deleted, or from someone just blocked) are dropped; pass "" when
 * `incoming` is the whole thread.
 */
export function mergeMessages<T extends { id: string; created_at: string }>(
  shown: T[],
  incoming: T[],
  replaceFrom?: string,
): T[] {
  const fresh = new Set(incoming.map((m) => m.id));
  const t = (iso: string) => Date.parse(iso) || 0;
  const cutoff = replaceFrom ? t(replaceFrom) : -Infinity;
  const kept = replaceFrom === undefined ? shown : shown.filter((m) => t(m.created_at) < cutoff || fresh.has(m.id));
  const byId = new Map(kept.map((m) => [m.id, m]));
  for (const m of incoming) byId.set(m.id, m);
  return [...byId.values()].sort((a, b) => t(a.created_at) - t(b.created_at) || a.id.localeCompare(b.id));
}
