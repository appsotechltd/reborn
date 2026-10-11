import { describe, expect, it } from "vitest";
import { threadComments } from "@/lib/comments";
import {
  embedSnippet,
  ideaIdFromUrl,
  reasonText,
  shareTargets,
  totalReactions,
  withFavorite,
  withReaction,
} from "@/lib/social";
import { isHalfVisible } from "@/lib/use-seen";
import type { Comment } from "@/lib/types";
import { makePost } from "./fixtures";

describe("optimistic post updates", () => {
  it("sets, switches and clears a reaction, keeping one per person", () => {
    let p = makePost({ viewer: { reaction: null, favorited: false, seen: false } });
    p = withReaction(p, "like");
    expect(p.viewer?.reaction).toBe("like");
    expect(p.stats.reactions).toEqual({ love: 2, like: 1 });
    p = withReaction(p, "love");
    expect(p.stats.reactions).toEqual({ love: 3 });
    p = withReaction(p, null);
    expect(p.viewer?.reaction).toBeNull();
    expect(p.stats.reactions).toEqual({ love: 2 });
    expect(totalReactions(p)).toBe(2);
  });

  it("favourites and unfavourites without double counting", () => {
    let p = makePost({ viewer: { reaction: null, favorited: false, seen: false } });
    p = withFavorite(p, true);
    expect(p.stats.favorites).toBe(6);
    p = withFavorite(p, true);
    expect(p.stats.favorites).toBe(6);
    p = withFavorite(p, false);
    expect(p.stats.favorites).toBe(5);
    expect(p.viewer?.favorited).toBe(false);
  });
});

describe("reasonText", () => {
  it("describes why a post is in the timeline", () => {
    expect(reasonText({ kind: "source", label: "Meditations" })).toBe("From Meditations");
    expect(reasonText({ kind: "author", label: "Marcus Aurelius" })).toBe("Because you follow Marcus Aurelius");
    expect(reasonText({ kind: "favorite", label: "Bob" })).toBe("Bob favourited this");
    expect(reasonText({ kind: "topic", label: "Psychology" })).toBe("Psychology");
    expect(reasonText(undefined)).toBeNull();
  });
});

describe("sharing and embedding", () => {
  it("builds share links that point at the canonical idea page", () => {
    const url = "https://reborn.example/ideas/example-book--01";
    const targets = shareTargets(url, "Small steps");
    expect(targets.map((t) => t.channel)).toEqual(["facebook", "x", "whatsapp", "linkedin", "telegram", "email"]);
    for (const t of targets) expect(t.href).toContain(encodeURIComponent(url));
  });

  it("escapes the title in the iframe snippet", () => {
    const html = embedSnippet("https://reborn.example", "example-book--01", 'Say "no" <now>');
    expect(html).toContain('src="https://reborn.example/embed/ideas/example-book--01"');
    expect(html).toContain("Say &quot;no&quot; &lt;now>");
  });

  it("only accepts idea URLs on this site for oEmbed", () => {
    const site = "https://reborn.example";
    expect(ideaIdFromUrl("https://reborn.example/ideas/example-book--01", site)).toBe("example-book--01");
    expect(ideaIdFromUrl("https://reborn.example/embed/ideas/example-book--01", site)).toBe("example-book--01");
    expect(ideaIdFromUrl("https://evil.example/ideas/example-book--01", site)).toBeNull();
    expect(ideaIdFromUrl("https://reborn.example/sources/example-book", site)).toBeNull();
    expect(ideaIdFromUrl("not a url", site)).toBeNull();
  });
});

describe("threadComments", () => {
  const c = (id: string, parent_id: string | null = null): Comment => ({
    id,
    post_id: "p",
    parent_id,
    body: id,
    author: { id: "u", handle: "ada", display_name: "Ada" },
    created_at: "2026-10-10T09:00:00Z",
  });

  it("nests replies under their top-level comment and keeps orphans", () => {
    const threads = threadComments([c("a"), c("b"), c("a1", "a"), c("x1", "missing"), c("b1", "b"), c("a2", "a")]);
    expect(threads.map((t) => [t.comment.id, t.replies.map((r) => r.id)])).toEqual([
      ["a", ["a1", "a2"]],
      ["b", ["b1"]],
      ["x1", []],
    ]);
  });
});

describe("isHalfVisible", () => {
  const rect = (height: number) => ({ height }) as DOMRectReadOnly;
  it("needs half the post on screen, or half the viewport for tall posts", () => {
    expect(isHalfVisible({ isIntersecting: true, intersectionRatio: 0.6, intersectionRect: rect(300), rootBounds: rect(800) })).toBe(true);
    expect(isHalfVisible({ isIntersecting: true, intersectionRatio: 0.3, intersectionRect: rect(200), rootBounds: rect(800) })).toBe(false);
    expect(isHalfVisible({ isIntersecting: true, intersectionRatio: 0.3, intersectionRect: rect(500), rootBounds: rect(800) })).toBe(true);
    expect(isHalfVisible({ isIntersecting: false, intersectionRatio: 0, intersectionRect: rect(0), rootBounds: rect(800) })).toBe(false);
  });
});
