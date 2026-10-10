import type { Card } from "./types";

export type CitationSegment =
  | { type: "text"; text: string }
  | { type: "citation"; id: string; card?: Card; index: number };

// Card ids are `<source-id>--<nn>`: lowercase slug, double hyphen, digits.
const CITATION_RE = /\[([a-z0-9]+(?:-[a-z0-9]+)*--[0-9]+)\]/g;

/**
 * Split an agent reply into text and `[card-id]` citation segments. `index` is the
 * 1-based position of the card in `citations` (order of first mention), or the
 * order of first appearance in the text when the card is missing from `citations`.
 */
export function parseCitations(reply: string, citations: Card[] = []): CitationSegment[] {
  const byId = new Map(citations.map((c) => [c.id, c]));
  const order = new Map(citations.map((c, i) => [c.id, i + 1]));
  const segments: CitationSegment[] = [];
  let last = 0;
  for (const match of reply.matchAll(CITATION_RE)) {
    const start = match.index ?? 0;
    if (start > last) segments.push({ type: "text", text: reply.slice(last, start) });
    const id = match[1];
    if (!order.has(id)) order.set(id, order.size + 1);
    segments.push({ type: "citation", id, card: byId.get(id), index: order.get(id)! });
    last = start + match[0].length;
  }
  if (last < reply.length) segments.push({ type: "text", text: reply.slice(last) });
  return segments;
}
