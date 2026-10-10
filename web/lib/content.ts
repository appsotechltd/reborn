import type { Card, Licence, SourceKind, Topic } from "./types";

/** Topic list from content/SCHEMA.md; used as a fallback when the API is down. */
export const TOPICS: { slug: string; name: string }[] = [
  { slug: "business", name: "Business" },
  { slug: "psychology", name: "Psychology" },
  { slug: "health", name: "Health & Wellness" },
  { slug: "emotional-intelligence", name: "Emotional Intelligence" },
  { slug: "personal-development", name: "Personal Development" },
  { slug: "productivity", name: "Productivity & Career" },
  { slug: "money", name: "Money" },
  { slug: "relationships", name: "Relationships" },
  { slug: "mindfulness", name: "Mindfulness & Philosophy" },
  { slug: "faith-wisdom", name: "Faith & Wisdom" },
  { slug: "leadership", name: "Leadership" },
  { slug: "parenting", name: "Parenting & Family" },
  { slug: "communication", name: "Communication & Influence" },
  { slug: "creativity", name: "Creativity" },
  { slug: "learning", name: "Learning & Thinking" },
  { slug: "lives-history", name: "Lives & History" },
  { slug: "entrepreneurship", name: "Entrepreneurship" },
];

export function topicName(slug: string, topics?: Pick<Topic, "slug" | "name">[]): string {
  const list = topics && topics.length ? topics : TOPICS;
  return list.find((t) => t.slug === slug)?.name ?? slug.replace(/-/g, " ");
}

export const LICENCES: Record<Licence, { name: string; quotes: boolean }> = {
  "public-domain": { name: "Public domain", quotes: true },
  "us-gov-public-domain": { name: "US Government work, public domain", quotes: true },
  "cc-by-4.0": { name: "CC BY 4.0", quotes: true },
  "cc-by-3.0": { name: "CC BY 3.0", quotes: true },
  "cc-by-sa-4.0": { name: "CC BY-SA 4.0", quotes: true },
  "cc0-1.0": { name: "CC0 1.0", quotes: true },
  "ogl-3.0": { name: "Open Government Licence v3.0", quotes: true },
  "original-summary": { name: "Original summary, linked to the source", quotes: false },
};

export function licenceName(code: string): string {
  return (LICENCES as Record<string, { name: string }>)[code]?.name ?? code;
}

export const SOURCE_KINDS: SourceKind[] = [
  "book",
  "textbook",
  "article",
  "guide",
  "study",
  "talk",
  "podcast",
  "video",
];

export function formatAuthors(authors: string[]): string {
  if (authors.length <= 1) return authors[0] ?? "";
  if (authors.length === 2) return `${authors[0]} and ${authors[1]}`;
  return `${authors.slice(0, -1).join(", ")} and ${authors[authors.length - 1]}`;
}

export function formatYear(year: number): string {
  return year < 0 ? `${-year} BCE` : String(year);
}

/** Body paragraphs: blank line separates paragraphs (content/SCHEMA.md). */
export function paragraphs(body: string): string[] {
  return body
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .filter(Boolean);
}

/** Short plain-text summary for meta descriptions. */
export function excerpt(text: string, max = 160): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (flat.length <= max) return flat;
  const cut = flat.slice(0, max - 1);
  return `${cut.slice(0, cut.lastIndexOf(" ") > 80 ? cut.lastIndexOf(" ") : cut.length)}…`;
}

/** Text read aloud by the Listen button. */
export function speechText(card: Pick<Card, "title" | "body" | "quote" | "apply_it">): string {
  return [card.title, card.body, card.quote ? `Quote: ${card.quote}` : "", `Apply it: ${card.apply_it}`]
    .filter(Boolean)
    .join("\n\n");
}
