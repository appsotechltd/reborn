import type { Ref } from "react";
import { reasonText } from "@/lib/social";
import type { Post, PostReason } from "@/lib/types";
import { topicName } from "@/lib/content";
import { CardView } from "./CardView";
import { Icon, type IconName } from "./Icon";
import { PostActions } from "./PostActions";
import { PostCover } from "./Polish";

const REASON_ICON: Record<string, IconName> = {
  source: "book",
  author: "person",
  writer: "person",
  favorite: "favoriteBorder",
  topic: "tag",
};

/** The small "why you're seeing this" line at the top of a timeline post, with its icon (as in the app). */
export function PostReasonLine({ reason, snap = false }: { reason: PostReason; snap?: boolean }) {
  const text = reasonText(reason);
  if (!text) return null;
  return (
    <p
      className={`mx-auto mb-3 flex max-w-read items-center gap-1.5 text-sm text-muted ${snap ? "max-md:mb-2 max-md:w-full max-md:text-xs" : ""}`}
      data-testid="post-reason"
    >
      <Icon name={REASON_ICON[reason.kind] ?? "sparkle"} className="size-3.5" />
      <span className="min-w-0 truncate">{text}</span>
    </p>
  );
}

/**
 * A post in a list (timeline, favourites, profiles): the card with credit and licence, plus its actions.
 *
 * With `snap`, below the md breakpoint the post fits its slide in the full-screen feed with no
 * scrolling inside it (a swipe always moves to the next post): a preview card (a cover with the
 * picture or the quote and the topic, why it's here, title, source, the body cut to the lines that
 * fit, "Read the idea" for the card's page and Listen), with the
 * action bar under the card so react, favourite, comments, share and gift are always in reach.
 * From md up it is the full card with its actions inside, as in other lists.
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
  const reason = showReason && post.reason ? post.reason : null;
  // A video post opens with its video; every other phone feed post opens with a cover.
  const card = post.card;
  const cover = snap && !card.explainer && !card.video?.scenes?.length;
  return (
    <div
      ref={trackRef}
      data-post-id={post.id}
      className={`panel px-5 py-6 sm:px-8 sm:py-8 ${
        snap
          ? "md:max-lg:px-5 md:max-lg:py-6 max-md:flex max-md:h-full max-md:flex-col max-md:rounded-none max-md:border-0 max-md:bg-transparent max-md:p-0 max-md:shadow-none"
          : ""
      }`}
    >
      <div
        className={
          snap
            ? "max-md:flex max-md:min-h-0 max-md:flex-1 max-md:flex-col max-md:overflow-clip max-md:rounded-[1.5rem] max-md:border max-md:border-[var(--post-border)] max-md:bg-surface max-md:px-5 max-md:pb-3.5 max-md:pt-3.5 max-md:shadow-[var(--card-shadow)]"
            : undefined
        }
      >
        {cover ? <PostCover card={card} topic={topicName(card.topic)} className="-mx-5 -mt-3.5 mb-3.5 md:hidden" /> : null}
        {reason ? <PostReasonLine reason={reason} snap={snap} /> : null}
        <CardView card={post.card} headingLevel="h2" titleHref={`/ideas/${post.id}`} feed={snap} />
      </div>
      <PostActions post={post} compact={snap} listen className={snap ? "mt-6 max-md:mt-2 max-md:shrink-0 max-md:px-1" : undefined} />
    </div>
  );
}
