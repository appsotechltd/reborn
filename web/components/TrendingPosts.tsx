"use client";

import { useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { TOPICS } from "@/lib/content";
import type { Post } from "@/lib/types";
import { PostPreviewList } from "./PostPreview";
import { ErrorNote } from "./SignInPrompt";

/** Trending posts with a topic filter. The unfiltered list is server-rendered. */
export function TrendingPosts({ initial }: { initial: Post[] }) {
  const { api } = useAuth();
  const [topic, setTopic] = useState("");
  const [lists, setLists] = useState<Record<string, Post[]>>({ "": initial });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function choose(slug: string) {
    setTopic(slug);
    setError(null);
    if (lists[slug]) return;
    setLoading(true);
    try {
      const r = await api.trending({ topic: slug || undefined, limit: 10 });
      setLists((l) => ({ ...l, [slug]: r.posts }));
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load trending ideas.");
    } finally {
      setLoading(false);
    }
  }

  const posts = lists[topic];
  return (
    <>
      <div role="group" aria-label="Filter by topic" className="flex flex-wrap gap-2">
        {[{ slug: "", name: "All topics" }, ...TOPICS].map((t) => (
          <button
            key={t.slug}
            type="button"
            aria-pressed={topic === t.slug}
            onClick={() => choose(t.slug)}
            className={`chip min-h-8 ${topic === t.slug ? "bg-accent-soft font-semibold text-fg" : "hover:text-fg"}`}
          >
            {t.name}
          </button>
        ))}
      </div>
      <ErrorNote error={error} />
      <div className="mt-4" aria-busy={loading}>
        {loading && !posts ? (
          <p role="status" className="text-muted">
            Loading…
          </p>
        ) : posts?.length ? (
          <PostPreviewList posts={posts} ranked />
        ) : posts ? (
          <p className="text-muted">Nothing trending in this topic yet. Be the first to react to something.</p>
        ) : null}
      </div>
    </>
  );
}
