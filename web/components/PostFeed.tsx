"use client";

import { useCallback, useState } from "react";
import { isApiError } from "@/lib/api";
import { useLoad } from "@/lib/use-load";
import type { PostsResponse } from "@/lib/types";
import { LoadMoreSentinel } from "./LoadMoreSentinel";
import { PostCard } from "./PostCard";
import { ErrorNote, Loading } from "./SignInPrompt";

/**
 * A paged list of posts (favourites, a profile's favourites). `load` must be
 * memoised; a new `load` starts over from the first page.
 */
export function PostFeed({
  load,
  empty,
}: {
  load: (cursor: string | null) => Promise<PostsResponse>;
  empty: React.ReactNode;
}) {
  const first = useCallback(() => load(null), [load]);
  const { data, error, loading, setData } = useLoad(first);
  const [more, setMore] = useState<{ loading: boolean; error: string | null }>({ loading: false, error: null });

  const loadMore = useCallback(async () => {
    if (!data?.next_cursor || more.loading) return;
    setMore({ loading: true, error: null });
    try {
      const page = await load(data.next_cursor);
      setData((prev) => {
        const posts = prev?.posts ?? [];
        return {
          posts: [...posts, ...page.posts.filter((p) => !posts.some((o) => o.id === p.id))],
          next_cursor: page.next_cursor,
        };
      });
      setMore({ loading: false, error: null });
    } catch (err) {
      setMore({ loading: false, error: isApiError(err) ? err.message : "Couldn't load more." });
    }
  }, [data, more.loading, load, setData]);

  if (loading) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  if (!data?.posts.length) return <>{empty}</>;

  return (
    <>
      <ul className="grid gap-6">
        {data.posts.map((p) => (
          <li key={p.id}>
            <PostCard post={p} />
          </li>
        ))}
      </ul>
      <ErrorNote error={more.error} />
      {data.next_cursor ? <LoadMoreSentinel onVisible={loadMore} loading={more.loading} /> : null}
    </>
  );
}
