import Link from "next/link";
import { excerpt, topicName } from "@/lib/content";
import { formatCount, totalReactions } from "@/lib/social";
import type { Post } from "@/lib/types";

/** Compact post for lists such as Discover: title, excerpt, credit and how people responded. */
export function PostPreview({ post, rank }: { post: Post; rank?: number }) {
  const { card, stats } = post;
  const reactions = totalReactions(post);
  return (
    <li className="panel relative flex gap-4 p-5 transition-colors hover:border-accent focus-within:border-accent">
      {rank ? (
        <span aria-hidden="true" className="font-serif text-2xl font-semibold text-muted">
          {rank}
        </span>
      ) : null}
      <div className="min-w-0">
        <p className="eyebrow">{topicName(card.topic)}</p>
        <h3 className="mt-1 font-serif text-xl font-semibold leading-snug">
          <Link href={`/ideas/${card.id}`} className="after:absolute after:inset-0 hover:underline focus-visible:outline-none">
            {card.title}
          </Link>
        </h3>
        <p className="mt-2 text-[0.9375rem] leading-relaxed text-muted">{excerpt(card.body, 130)}</p>
        <p className="mt-3 text-xs text-muted">{card.credit}</p>
        <p className="mt-2 flex flex-wrap gap-3 text-xs text-muted" aria-label="Responses">
          <span>{formatCount(reactions)} {reactions === 1 ? "reaction" : "reactions"}</span>
          <span>{formatCount(stats.comments)} {stats.comments === 1 ? "comment" : "comments"}</span>
          <span>{formatCount(stats.favorites)} {stats.favorites === 1 ? "favourite" : "favourites"}</span>
        </p>
      </div>
    </li>
  );
}

export function PostPreviewList({ posts, ranked = false }: { posts: Post[]; ranked?: boolean }) {
  return (
    <ul className="grid gap-4 sm:grid-cols-2">
      {posts.map((p, i) => (
        <PostPreview key={p.id} post={p} rank={ranked ? i + 1 : undefined} />
      ))}
    </ul>
  );
}
