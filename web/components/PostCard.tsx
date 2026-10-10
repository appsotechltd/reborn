import type { Ref } from "react";
import { reasonText } from "@/lib/social";
import type { Post } from "@/lib/types";
import { CardView } from "./CardView";
import { PostActions } from "./PostActions";

/** A post in a list (timeline, favourites, profiles): the card with credit and licence, plus its actions. */
export function PostCard({
  post,
  showReason = false,
  trackRef,
}: {
  post: Post;
  showReason?: boolean;
  /** Attached to the post so the timeline can tell when it has been seen. */
  trackRef?: Ref<HTMLDivElement>;
}) {
  const reason = showReason ? reasonText(post.reason) : null;
  return (
    <div ref={trackRef} data-post-id={post.id} className="panel px-5 py-6 sm:px-8 sm:py-8">
      {reason ? (
        <p className="mx-auto mb-3 max-w-read text-sm text-muted" data-testid="post-reason">
          {reason}
        </p>
      ) : null}
      <CardView card={post.card} headingLevel="h2" titleHref={`/ideas/${post.id}`} />
      <PostActions post={post} />
    </div>
  );
}
