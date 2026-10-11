import type { Post, PostReason, ReactionKind, ShareChannel } from "./types";

export const REACTIONS: { kind: ReactionKind; emoji: string; label: string }[] = [
  { kind: "like", emoji: "👍", label: "Like" },
  { kind: "love", emoji: "😍", label: "Love" },
  { kind: "insightful", emoji: "💡", label: "Insightful" },
  { kind: "inspiring", emoji: "✨", label: "Inspiring" },
  { kind: "helpful", emoji: "🙌", label: "Helpful" },
];

export function reactionInfo(kind: ReactionKind) {
  return REACTIONS.find((r) => r.kind === kind) ?? REACTIONS[0];
}

export function totalReactions(post: Pick<Post, "stats">): number {
  return Object.values(post.stats.reactions ?? {}).reduce((a, b) => a + (b ?? 0), 0);
}

/**
 * Optimistically set (or clear, with null) the viewer's reaction, keeping counts
 * in step: one reaction per person, so the previous one is taken back.
 */
export function withReaction(post: Post, kind: ReactionKind | null): Post {
  const prev = post.viewer?.reaction ?? null;
  const reactions = { ...post.stats.reactions };
  if (prev) reactions[prev] = Math.max(0, (reactions[prev] ?? 0) - 1);
  if (kind) reactions[kind] = (reactions[kind] ?? 0) + 1;
  for (const k of Object.keys(reactions) as ReactionKind[]) if (!reactions[k]) delete reactions[k];
  return {
    ...post,
    stats: { ...post.stats, reactions },
    viewer: { favorited: false, seen: false, ...post.viewer, reaction: kind },
  };
}

/** Optimistically favourite or unfavourite a post. */
export function withFavorite(post: Post, on: boolean): Post {
  const was = post.viewer?.favorited ?? false;
  const delta = on === was ? 0 : on ? 1 : -1;
  return {
    ...post,
    stats: { ...post.stats, favorites: Math.max(0, post.stats.favorites + delta) },
    viewer: { reaction: null, seen: false, ...post.viewer, favorited: on },
  };
}

/** The small "why you're seeing this" line above a timeline post. */
export function reasonText(reason: PostReason | null | undefined): string | null {
  if (!reason) return null;
  switch (reason.kind) {
    case "source":
      return reason.label ? `From ${reason.label}` : null;
    case "author":
      return reason.label ? `Because you follow ${reason.label}` : null;
    case "favorite":
      return reason.label ? `${reason.label} favourited this` : null;
    case "topic":
      return reason.label ? `In ${reason.label}, one of your topics` : null;
    case "new":
      return "New on Reborn";
    default:
      return reason.label || null;
  }
}

export function authorHref(name: string): string {
  return `/authors/${encodeURIComponent(name)}`;
}

export function ideaPath(id: string): string {
  return `/ideas/${id}`;
}

export function embedSnippet(siteUrl: string, id: string, title: string): string {
  const src = `${siteUrl}/embed/ideas/${encodeURIComponent(id)}`;
  const safeTitle = title.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  return `<iframe src="${src}" title="${safeTitle} · Reborn" width="560" height="560" style="border:0;max-width:100%" loading="lazy"></iframe>`;
}

export type ShareTarget = { channel: ShareChannel; label: string; href: string };

/** Share links for the networks that have a web share URL. Instagram has none: use Copy link or the share sheet. */
export function shareTargets(url: string, title: string): ShareTarget[] {
  const u = encodeURIComponent(url);
  const t = encodeURIComponent(title);
  const both = encodeURIComponent(`${title} ${url}`);
  return [
    { channel: "facebook", label: "Facebook", href: `https://www.facebook.com/sharer/sharer.php?u=${u}` },
    { channel: "x", label: "X", href: `https://x.com/intent/post?url=${u}&text=${t}` },
    { channel: "whatsapp", label: "WhatsApp", href: `https://wa.me/?text=${both}` },
    { channel: "linkedin", label: "LinkedIn", href: `https://www.linkedin.com/sharing/share-offsite/?url=${u}` },
    { channel: "telegram", label: "Telegram", href: `https://t.me/share/url?url=${u}&text=${t}` },
    {
      channel: "email",
      label: "Email",
      href: `mailto:?subject=${t}&body=${encodeURIComponent(`${title}\n\n${url}`)}`,
    },
  ];
}

export function formatMoney(cents: number, currency: string): string {
  try {
    return new Intl.NumberFormat("en", { style: "currency", currency: currency.toUpperCase() }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency.toUpperCase()}`;
  }
}

export function formatCount(n: number): string {
  if (n < 1000) return String(n);
  if (n < 1_000_000) return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0).replace(/\.0$/, "")}k`;
  return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
}

export function timeAgo(iso: string, now = Date.now()): string {
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
  if (s < 60) return "just now";
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} h ago`;
  const d = Math.round(h / 24);
  if (d < 30) return `${d} d ago`;
  return new Date(iso).toLocaleDateString();
}

/** Card id from an idea or embed URL on this site, or null. */
export function ideaIdFromUrl(raw: string, site: string, alsoHost?: string | null): string | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.host !== new URL(site).host && url.host !== alsoHost) return null;
  const m = url.pathname.match(/^\/(?:embed\/)?ideas\/([^/]+)\/?$/);
  return m ? decodeURIComponent(m[1]) : null;
}
