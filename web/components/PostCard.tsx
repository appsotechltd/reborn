import type { Ref } from "react";
import { reasonText } from "@/lib/social";
import type { Post } from "@/lib/types";
import { CardView } from "./CardView";
import { PostActions } from "./PostActions";

/**
 * A post in a list (timeline, favourites, profiles): the card with credit and licence, plus its actions.
 *
 * With `snap`, below the md breakpoint the post fills its slide in the full-screen feed: the card
 * scrolls inside the slide when it is long, and the actions stay pinned at the bottom so react,
 * favourite, comments and share are always in reach.
 */
export function PostCard({
  post,
  showReason = false,
  trackRef,
  snap = false,
}: {
  post: Post;
  showReason?: boolean;
  /** Attached to the post so the timeline can tell when it has been seen. */
  trackRef?: Ref<HTMLDivElement>;
  /** Part of the home feed: fills a full-screen slide on phones and autoplays its video. */
  snap?: boolean;
}) {
  const reason = showReason ? reasonText(post.reason) : null;
  return (
    <div
      ref={trackRef}
      data-post-id={post.id}
      className={`panel px-5 py-6 sm:px-8 sm:py-8 ${snap ? "max-md:flex max-md:h-full max-md:flex-col max-md:px-4 max-md:pb-2 max-md:pt-4" : ""}`}
    >
      <div
        data-slide-scroll={snap ? "" : undefined}
        className={
          snap
            ? "max-md:-mx-1 max-md:min-h-0 max-md:flex-1 max-md:overflow-y-auto max-md:px-1 max-md:pb-6 max-md:[mask-image:linear-gradient(to_bottom,#000_calc(100%-1.5rem),transparent)]"
            : undefined
        }
      >
        {reason ? (
          <p className="mx-auto mb-3 max-w-read text-sm text-muted" data-testid="post-reason">
            {reason}
          </p>
        ) : null}
        <CardView card={post.card} headingLevel="h2" titleHref={`/ideas/${post.id}`} feed={snap} />
      </div>
      <PostActions post={post} compact={snap} className={snap ? "mt-6 max-md:mt-0 max-md:shrink-0" : undefined} />
    </div>
  );
}
