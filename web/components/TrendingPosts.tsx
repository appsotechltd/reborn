"use client";

import { useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { TOPICS, topicName } from "@/lib/content";
import type { Post } from "@/lib/types";
import { ChipRow } from "./ChipRow";
import { PostPreviewList } from "./PostPreview";
import { ErrorNote } from "./SignInPrompt";

interface TopicList {
  posts: Post[];
  /** Nothing was trending in the topic, so these are its newest ideas instead. */
  newest?: boolean;
}

/**
 * Trending posts with a topic filter. The unfiltered list is server-rendered. A topic
 * with nothing trending this week (no reactions, comments or saves yet) falls back to
 * its newest ideas, so a filter never ends in an empty list while the topic has cards.
 */
export function TrendingPosts({ initial }: { initial: Post[] }) {
  const { api } = useAuth();
  const [topic, setTopic] = useState("");
  const [lists, setLists] = useState<Record<string, TopicList>>({ "": { posts: initial } });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function choose(slug: string) {
    setTopic(slug);
    setError(null);
    if (lists[slug]) return;
    setLoading(true);
    try {
      const r = await api.trending({ topic: slug || undefined, limit: 10 });
      let list: TopicList = { posts: r.posts };
      if (!r.posts.length && slug) {
        const newest = await api.timeline({ topics: slug, limit: 10 }, false);
        list = { posts: newest.posts, newest: true };
      }
      setLists((l) => ({ ...l, [slug]: list }));
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load trending ideas.");
    } finally {
      setLoading(false);
    }
  }

  const list = lists[topic];
  const posts = list?.posts;
  return (
    <>
      <ChipRow
        label="Filter by topic"
        className="max-md:-mx-4"
        scrollClassName="flex flex-wrap gap-2 max-md:flex-nowrap max-md:overflow-x-auto max-md:px-4 max-md:pb-1 max-md:[scrollbar-width:none]"
      >
        {[{ slug: "", name: "All topics" }, ...TOPICS].map((t) => (
          <button
            key={t.slug}
            type="button"
            aria-pressed={topic === t.slug}
            onClick={() => choose(t.slug)}
            className={`chip min-h-8 shrink-0 pointer-coarse:min-h-11 ${topic === t.slug ? "chip-on" : "hover:text-fg"}`}
          >
            {t.name}
          </button>
        ))}
      </ChipRow>
      <ErrorNote error={error} />
      <div className="mt-4" aria-busy={loading}>
        {loading && !posts ? (
          <p role="status" className="text-muted">
            Loading…
          </p>
        ) : posts?.length ? (
          <>
            {list.newest ? (
              <p role="status" className="mb-3 text-sm text-muted">
                Nothing trending in {topicName(topic)} this week yet. Here are its newest ideas.
              </p>
            ) : null}
            <PostPreviewList posts={posts} ranked={!list.newest} />
          </>
        ) : posts ? (
          <p className="text-muted">No ideas in this topic yet.</p>
        ) : null}
      </div>
    </>
  );
}
