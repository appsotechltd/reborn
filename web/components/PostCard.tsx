import type { Ref } from "react";
import { reasonText } from "@/lib/social";
import type { Post } from "@/lib/types";
import { CardView } from "./CardView";
import { PostActions } from "./PostActions";

/**
 * A post in a list (timeline, favourites, profiles): the card with credit and licence, plus its actions.
 *
 * With `snap`, below the md breakpoint the post fits its slide in the full-screen feed with no
 * scrolling inside it (a swipe always moves to the next post): a preview of the card with
 * "Read more" opening the card's page, and the actions pinned at the bottom so react, favourite,
 * comments and share are always in reach. From md up it is the full card, as in other lists.
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
      <div className={snap ? "max-md:flex max-md:min-h-0 max-md:flex-1 max-md:flex-col max-md:overflow-clip max-md:pb-3 max-md:[overflow-clip-margin:0.5rem]" : undefined}>
        {reason ? (
          <p
            className={`mx-auto mb-3 max-w-read text-sm text-muted ${snap ? "max-md:mb-2 max-md:w-full max-md:truncate" : ""}`}
            data-testid="post-reason"
          >
            {reason}
          </p>
        ) : null}
        <CardView card={post.card} headingLevel="h2" titleHref={`/ideas/${post.id}`} feed={snap} />
      </div>
      <PostActions post={post} compact={snap} className={snap ? "mt-6 max-md:mt-0 max-md:shrink-0" : undefined} />
    </div>
  );
}
