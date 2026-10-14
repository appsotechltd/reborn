"use client";

import Link from "next/link";
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useSeenTracker } from "@/lib/use-seen";
import { useListen, useListenFollow } from "@/lib/listen";
import { itemsFromPosts } from "@/lib/listen-player";
import { postOnScreen, useHeaderHeightVar, useSnapFeedKeys } from "@/lib/use-snap-feed";
import { isSummaryItem, type Post, type TimelineItem, type Topic } from "@/lib/types";
import { ChipRow } from "./ChipRow";
import { DailyBanner } from "./DailyBanner";
import { Icon } from "./Icon";
import { LoadMoreSentinel } from "./LoadMoreSentinel";
import { PostCard } from "./PostCard";
import { ErrorNote } from "./SignInPrompt";
import { StreakWidget } from "./StreakWidget";
import { SummaryPost } from "./SummaryPost";

const PAGE = 10;
const ANON = "anon";
/** Start loading the next page about three screens ahead: 2-3 posts from the end in the phone feed. */
const PRELOAD_MARGIN = "0px 0px 300% 0px";
/** In the phone feed, moving to one of the last few posts loads the next page. */
const PRELOAD_POSTS = 3;
/** Listen mode follows the post on screen once scrolling has rested this long (ms). */
const FOLLOW_AFTER_MS = 500;

interface FeedState {
  /** Whose timeline this is (ANON, or the token it was loaded with) and its topic filter: `${who}|${topic}`. */
  key: string;
  posts: TimelineItem[];
  cursor: string | null;
}

/** Index of the first post the viewer had already seen, where "You're all caught up" goes. */
export function caughtUpIndex(posts: TimelineItem[]): number {
  return posts.findIndex((p) => !isSummaryItem(p) && p.viewer?.seen === true);
}

/** The card posts, leaving out summary posts (Listen mode plays cards one by one). */
export function cardPosts(items: TimelineItem[]): Post[] {
  return items.filter((p): p is Post => !isSummaryItem(p));
}

/**
 * The home timeline. Starts from the anonymous first page rendered on the server
 * (for crawlers and signed-out visitors), then swaps in the signed-in reader's
 * own timeline. Scrolls endlessly (unseen posts first, then older ones, as the API
 * orders them) and marks posts seen as they are read.
 *
 * Below the md breakpoint it is a full-screen vertical feed: one post per screen,
 * snapping one post at a time (CSS scroll-snap on the page, see globals.css), with
 * j/k and the arrow keys moving one post. From md up it is a column of posts.
 */
export function Timeline({
  initialPosts,
  initialCursor,
  topics = [],
}: {
  initialPosts: TimelineItem[];
  initialCursor: string | null;
  /** For the phone feed's topic chips ("For you" and one per topic), as in the app. */
  topics?: Pick<Topic, "slug" | "name">[];
}) {
  const { ready, token, user, api } = useAuth();
  const [topic, setTopic] = useState("");
  const [feed, setFeed] = useState<FeedState>({ key: `${ANON}|`, posts: initialPosts, cursor: initialCursor });
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [moreError, setMoreError] = useState<string | null>(null);
  const listRef = useRef<HTMLOListElement>(null);
  const who = token ?? ANON;
  const wanted = `${who}|${topic}`;
  const switching = ready && feed.key !== wanted;
  const busy = useRef(false);

  useEffect(() => {
    if (!ready || feed.key === wanted) return;
    let cancelled = false;
    api
      .timelineWithSummaries({ limit: PAGE, topics: topic || undefined }, who !== ANON)
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
  }, [ready, wanted, who, topic, feed.key, api]);

  const loadMore = useCallback(async () => {
    if (!feed.cursor || busy.current || switching) return;
    busy.current = true;
    setLoadingMore(true);
    setMoreError(null);
    const key = feed.key;
    const [keyWho, keyTopic] = key.split("|");
    try {
      const page = await api.timelineWithSummaries(
        { cursor: feed.cursor, limit: PAGE, topics: keyTopic || undefined },
        keyWho !== ANON,
      );
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
      setMoreError(isApiError(err) ? err.message : "Couldn't load more ideas.");
    } finally {
      busy.current = false;
      setLoadingMore(false);
    }
  }, [api, feed.cursor, feed.key, switching]);

  const signedIn = !feed.key.startsWith(`${ANON}|`);
  const track = useSeenTracker(api, signedIn && !!user);
  const divider = signedIn ? caughtUpIndex(feed.posts) : -1;

  useHeaderHeightVar();
  useSnapFeedKeys(listRef, (index, count) => {
    if (count - 1 - index < PRELOAD_POSTS) void loadMore();
  });

  const { player } = useListen();
  // Only once hydrated: whether the device voice exists is known only in the browser.
  const listenable = ready && !!player && !switching && cardPosts(feed.posts).some((p) => player.canPlay(p.card));

  const feedTopics = feed.key.split("|")[1] ?? "";
  const listenQueue = `timeline|${feedTopics}`;

  /** Listen mode from the post on screen (or the top), with the feed's topic filter. */
  function listen() {
    if (!player) return;
    const from = Math.min(postOnScreen(listRef.current), Math.max(0, feed.posts.length - 1));
    player.start({
      items: itemsFromPosts(cardPosts(feed.posts.slice(from))),
      cursor: feed.cursor,
      topics: feedTopics,
      queue: listenQueue,
    });
  }

  // While a session is on, it follows the card post on screen (a summary post on screen leaves it be).
  const [onScreen, setOnScreen] = useState<string | null>(null);
  useEffect(() => {
    let t: number | undefined;
    const update = () => setOnScreen(feed.posts[postOnScreen(listRef.current)]?.id ?? null);
    const onScroll = () => {
      window.clearTimeout(t);
      t = window.setTimeout(update, FOLLOW_AFTER_MS);
    };
    t = window.setTimeout(update, 0);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.clearTimeout(t);
      window.removeEventListener("scroll", onScroll);
    };
  }, [feed.posts]);
  const cards = cardPosts(feed.posts);
  const onScreenCard = cards.findIndex((p) => p.id === onScreen);
  useListenFollow(
    ready && !switching && onScreenCard >= 0
      ? { items: itemsFromPosts(cards), index: onScreenCard, cursor: feed.cursor, topics: feedTopics, queue: listenQueue }
      : null,
  );

  function chooseTopic(slug: string) {
    if (slug === topic) return;
    setTopic(slug);
    window.scrollTo({ top: 0 });
  }

  // Above the first post: on phones these share its slide (as in the app), on wider screens they
  // stack above it as before.
  const lead = (
    <>
      <DailyBanner />
      {ready && !user ? <JoinPrompt /> : null}
      {user ? <StreakWidget /> : null}
    </>
  );

  return (
    <div className="mx-auto max-w-3xl">
      {topics.length ? (
        <TopicChips
          topics={topics}
          selected={topic}
          onSelect={chooseTopic}
          trailing={listenable ? <ListenFeedButton onClick={listen} compact /> : null}
        />
      ) : null}
      {listenable ? (
        <div className={`mb-4 flex justify-end ${topics.length ? "max-md:hidden" : "max-md:mb-2"}`}>
          <ListenFeedButton onClick={listen} />
        </div>
      ) : null}
      {switching && !error ? (
        <p role="status" className="mb-4 text-center text-sm text-muted">
          {feed.key.split("|")[0] === who ? "Loading…" : "Loading your timeline…"}
        </p>
      ) : null}
      {feed.posts.length === 0 && !switching ? (
        <>
          {lead}
          <p className="panel p-6 text-center text-muted">
            No ideas here yet.{" "}
            <Link href="/welcome?edit=1" className="link">
              Pick some topics
            </Link>{" "}
            or{" "}
            <Link href="/sources" className="link">
              browse the sources
            </Link>
            .
          </p>
        </>
      ) : (
        <ol ref={listRef} data-snap-feed className="grid gap-6 max-md:gap-0" aria-label="Timeline">
          {feed.posts.map((p, i) => (
            <li
              key={`${signedIn ? "me" : "anon"}:${p.id}`}
              className="max-md:flex max-md:h-[var(--slide-h)] max-md:snap-start max-md:snap-always max-md:flex-col max-md:pb-1 max-md:pt-2"
            >
              {i === 0 ? lead : null}
              {i === divider ? <CaughtUp /> : null}
              <div className="max-md:min-h-0 max-md:flex-1">
                {isSummaryItem(p) ? (
                  <SummaryPost summary={p.summary} snap />
                ) : (
                  <PostCard post={p} showReason snap trackRef={signedIn && !p.viewer?.seen ? track : undefined} />
                )}
              </div>
              {i === 0 && feed.posts.length > 1 ? <SwipeHint /> : null}
            </li>
          ))}
        </ol>
      )}
      <ErrorNote error={error} />
      {feed.cursor ? (
        <LoadMoreSentinel
          onVisible={loadMore}
          loading={loadingMore}
          error={moreError}
          rootMargin={PRELOAD_MARGIN}
          label="Load more ideas"
        />
      ) : feed.posts.length ? (
        <FeedEnd />
      ) : null}
    </div>
  );
}

/**
 * The phone feed's topic chips, as in the app: "For you" and each topic, filtering the feed in
 * place. They stay under the header while the feed snaps. Wider screens have the topic links
 * above the timeline instead.
 */
function TopicChips({
  topics,
  selected,
  onSelect,
  trailing,
}: {
  topics: Pick<Topic, "slug" | "name">[];
  selected: string;
  onSelect: (slug: string) => void;
  /** After the chips, not scrolling with them: the Listen button. */
  trailing?: ReactNode;
}) {
  return (
    <ChipRow
      data-feed-chips
      trailing={trailing}
      label="Filter the timeline by topic"
      className="sticky top-[var(--site-header-h,3.5rem)] z-[5] -mx-4 bg-bg md:hidden"
      scrollClassName="flex gap-2 overflow-x-auto px-3 [scrollbar-width:none]"
    >
      {[{ slug: "", name: "For you" }, ...topics].map((t) => {
        const on = selected === t.slug;
        return (
          <button
            key={t.slug}
            type="button"
            aria-pressed={on}
            onClick={() => onSelect(t.slug)}
            className="flex min-h-11 shrink-0 items-center"
          >
            <span
              className={`chip h-9 px-4 text-sm font-semibold ${on ? "chip-on" : "hover:text-fg"}`}
            >
              {t.name}
            </span>
          </button>
        );
      })}
    </ChipRow>
  );
}

/**
 * Starts Listen mode from the post on screen. On phones it is a headphones button at the end of the
 * topic chips (`compact`); on wider screens a "Listen" button above the timeline.
 */
function ListenFeedButton({ onClick, compact = false }: { onClick: () => void; compact?: boolean }) {
  if (compact) {
    return (
      <button
        type="button"
        onClick={onClick}
        aria-label="Listen to this feed"
        className="mr-1 grid size-11 place-items-center rounded-full text-accent-text hover:bg-surface-2"
      >
        <Icon name="headphones" className="size-6" />
      </button>
    );
  }
  return (
    <button type="button" onClick={onClick} className="btn btn-small" aria-label="Listen to this feed">
      <Icon name="headphones" className="size-4" />
      Listen
    </button>
  );
}

/** "Swipe up for the next idea", under the first post on phones. */
function SwipeHint() {
  return (
    <p aria-hidden="true" className="flex shrink-0 items-center justify-center gap-1 pt-1 text-xs text-muted md:hidden">
      <Icon name="arrowUp" className="size-4" />
      Swipe up for the next idea
    </p>
  );
}

/** The end of everything the timeline has: never a dead end, always somewhere to go next. */
function FeedEnd() {
  return (
    <section
      aria-label="End of the timeline"
      className="mt-8 text-center max-md:flex max-md:min-h-[50dvh] max-md:snap-start max-md:flex-col max-md:items-center max-md:justify-center"
    >
      <p className="text-sm text-muted">That&apos;s everything for now. Come back tomorrow for more.</p>
      <div className="mt-4 flex flex-wrap justify-center gap-3">
        <Link href="/discover" className="btn">
          Discover more ideas
        </Link>
        <Link href="/welcome?edit=1" className="btn">
          Follow more topics
        </Link>
      </div>
    </section>
  );
}

function CaughtUp() {
  return (
    <div
      role="separator"
      aria-label="You're all caught up"
      className="mb-6 flex items-center gap-3 text-sm text-muted max-md:mb-2 max-md:shrink-0"
    >
      <span className="h-px flex-1 bg-line" />
      <span className="font-semibold text-fg">You&apos;re all caught up</span>
      <span className="h-px flex-1 bg-line" />
    </div>
  );
}

function JoinPrompt() {
  return (
    <section
      aria-labelledby="join-title"
      data-join-prompt
      className="panel mb-6 bg-accent-soft p-5 text-center max-md:mb-2 max-md:shrink-0 max-md:p-4 max-md:text-left sm:p-6"
    >
      <h2 id="join-title" className="font-serif text-xl font-semibold max-md:text-lg">
        Make this timeline yours
      </h2>
      <p className="mt-1 text-muted max-md:text-sm">
        Follow books, authors and people, react and comment, and keep your favourites. It&apos;s free.
      </p>
      <div className="mt-4 flex flex-wrap justify-center gap-3 max-md:mt-3 max-md:justify-start max-md:gap-2">
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
