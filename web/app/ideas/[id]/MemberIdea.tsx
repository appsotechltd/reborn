"use client";

import { useCallback } from "react";
import { CardView } from "@/components/CardView";
import { Comments } from "@/components/Comments";
import { ListenButton } from "@/components/ListenButton";
import { PostActions } from "@/components/PostActions";
import { ErrorNote, Loading, SignInPrompt } from "@/components/SignInPrompt";
import { StashButton } from "@/components/StashButton";
import { ViewTracker } from "@/components/ViewTracker";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";

/**
 * A member's card that only some readers may see (their followers or subscribers, or the writer):
 * the server renders pages signed out, so the page loads it in the browser as the reader.
 */
export function MemberIdea({ id }: { id: string }) {
  const { api, ready, user, token } = useAuth();
  const loader = useCallback(() => api.post(id), [api, id, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: post, error, status, loading } = useLoad(ready && user ? loader : null);

  if (!ready || loading) return <Loading />;
  if (!user) {
    return <SignInPrompt message="This card is for its writer's followers or subscribers. Sign in to see if you can read it." />;
  }
  if (status === 404) {
    return (
      <div className="mx-auto max-w-read py-12 text-center">
        <h1 className="font-serif text-3xl font-semibold">Idea not found</h1>
        <p className="mt-2 text-muted">It may have been deleted, or it&apos;s only for its writer&apos;s followers or subscribers.</p>
      </div>
    );
  }
  if (error || !post) return <ErrorNote error={error ?? "Couldn't load this idea."} />;

  const card = post.card;
  return (
    <>
      <ViewTracker cardId={card.id} />
      <CardView
        card={card}
        actions={
          <>
            <ListenButton card={card} />
            <StashButton cardId={card.id} cardTitle={card.title} />
          </>
        }
      />
      <PostActions post={post} commentsHref="#comments" />
      <Comments postId={card.id} />
    </>
  );
}
