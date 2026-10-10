"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useSeenTracker } from "@/lib/use-seen";
import type { Post } from "@/lib/types";
import { LoadMoreSentinel } from "./LoadMoreSentinel";
import { PostCard } from "./PostCard";
import { ErrorNote } from "./SignInPrompt";

const PAGE = 10;
const ANON = "anon";

interface FeedState {
  /** Whose timeline this is: ANON, or the token it was loaded with. */
  key: string;
  posts: Post[];
  cursor: string | null;
}

/** Index of the first post the viewer had already seen, where "You're all caught up" goes. */
export function caughtUpIndex(posts: Post[]): number {
  return posts.findIndex((p) => p.viewer?.seen === true);
}

/**
 * The home timeline. Starts from the anonymous first page rendered on the server
 * (for crawlers and signed-out visitors), then swaps in the signed-in reader's
 * own timeline. Scrolls infinitely and marks posts seen as they are read.
 */
export function Timeline({ initialPosts, initialCursor }: { initialPosts: Post[]; initialCursor: string | null }) {
  const { ready, token, user, api } = useAuth();
  const [feed, setFeed] = useState<FeedState>({ key: ANON, posts: initialPosts, cursor: initialCursor });
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const wanted = token ?? ANON;
  const switching = ready && feed.key !== wanted;
  const busy = useRef(false);

  useEffect(() => {
    if (!ready || feed.key === wanted) return;
    let cancelled = false;
    api
      .timeline({ limit: PAGE }, wanted !== ANON)
      .then((page) => {
        if (cancelled) return;
        setFeed({ key: wanted, posts: page.posts, cursor: page.next_cursor });
        setError(null);
      })
      .catch((err) => {
        if (!cancelled) setError(isApiError(err) ? err.message : "Couldn't load your timeline.");
      });
    return () => {
      cancelled = true;
    };
  }, [ready, wanted, feed.key, api]);

  const loadMore = useCallback(async () => {
    if (!feed.cursor || busy.current || switching) return;
    busy.current = true;
    setLoadingMore(true);
    setError(null);
    const key = feed.key;
    try {
      const page = await api.timeline({ cursor: feed.cursor, limit: PAGE }, key !== ANON);
      setFeed((f) =>
        f.key !== key
          ? f
          : {
              key,
              posts: [...f.posts, ...page.posts.filter((p) => !f.posts.some((o) => o.id === p.id))],
              cursor: page.next_cursor,
            },
      );
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't load more ideas.");
    } finally {
      busy.current = false;
      setLoadingMore(false);
    }
  }, [api, feed.cursor, feed.key, switching]);

  const signedIn = feed.key !== ANON;
  const track = useSeenTracker(api, signedIn && !!user);
  const divider = signedIn ? caughtUpIndex(feed.posts) : -1;

  return (
    <div className="mx-auto max-w-3xl">
      {ready && !user ? <JoinPrompt /> : null}
      {switching && !error ? (
        <p role="status" className="mb-4 text-center text-sm text-muted">
          Loading your timeline…
        </p>
      ) : null}
      {feed.posts.length === 0 && !switching ? (
        <p className="panel p-6 text-center text-muted">
          No ideas here yet. Pick some topics in{" "}
          <Link href="/settings" className="link">
            Settings
          </Link>{" "}
          or{" "}
          <Link href="/sources" className="link">
            browse the sources
          </Link>
          .
        </p>
      ) : (
        <ol className="grid gap-6" aria-label="Timeline">
          {feed.posts.map((p, i) => (
            <li key={`${signedIn ? "me" : "anon"}:${p.id}`}>
              {i === divider ? <CaughtUp /> : null}
              <PostCard post={p} showReason trackRef={signedIn && !p.viewer?.seen ? track : undefined} />
            </li>
          ))}
        </ol>
      )}
      <ErrorNote error={error} />
      {feed.cursor ? (
        <LoadMoreSentinel onVisible={loadMore} loading={loadingMore} label="Load more ideas" />
      ) : feed.posts.length ? (
        <p className="mt-8 text-center text-sm text-muted">That&apos;s everything for now. Come back tomorrow for more.</p>
      ) : null}
    </div>
  );
}

function CaughtUp() {
  return (
    <div role="separator" aria-label="You're all caught up" className="mb-6 flex items-center gap-3 text-sm text-muted">
      <span className="h-px flex-1 bg-line" />
      <span className="font-semibold text-fg">You&apos;re all caught up</span>
      <span className="h-px flex-1 bg-line" />
    </div>
  );
}

function JoinPrompt() {
  return (
    <section aria-labelledby="join-title" className="panel mb-6 bg-accent-soft p-5 text-center sm:p-6">
      <h2 id="join-title" className="font-serif text-xl font-semibold">
        Make this timeline yours
      </h2>
      <p className="mt-1 text-muted">
        Follow books, authors and people, react and comment, and keep your favourites. It&apos;s free.
      </p>
      <div className="mt-4 flex flex-wrap justify-center gap-3">
        <Link href="/register" className="btn btn-primary">
          Create an account
        </Link>
        <Link href="/signin" className="btn">
          Sign in
        </Link>
      </div>
    </section>
  );
}
