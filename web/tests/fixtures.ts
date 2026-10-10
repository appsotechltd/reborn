import type { Card, Post } from "@/lib/types";

// Made-up ids: tests must not depend on real library content.
export function makeCard(overrides: Partial<Card> = {}): Card {
  return {
    id: "example-book--01",
    title: "Small steps beat big plans",
    body: "A first paragraph about taking small steps.\n\nA second paragraph about keeping going.",
    quote: null,
    apply_it: "Pick one tiny step and do it today.",
    topic: "personal-development",
    tags: ["habits"],
    locator: "Chapter 1",
    health: false,
    disclaimer: null,
    quiz: null,
    source: {
      id: "example-book",
      title: "An Example Book",
      authors: ["Ada Example"],
      kind: "book",
      url: "https://example.org/book",
      licence: "public-domain",
      licence_url: "https://example.org/licence",
      attribution: "Ada Example, An Example Book, public domain",
    },
    credit: "Source: Ada Example, An Example Book, public domain",
    ...overrides,
  };
}

export function makePost(overrides: Partial<Post> = {}): Post {
  const card = overrides.card ?? makeCard();
  return {
    id: card.id,
    published_at: "2026-10-10T09:00:00Z",
    card,
    stats: { reactions: { love: 2 }, comments: 3, favorites: 5, shares: 0, gifts: 0 },
    ...overrides,
  };
}
