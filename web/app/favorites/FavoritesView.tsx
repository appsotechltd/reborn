"use client";

import Link from "next/link";
import { useCallback } from "react";
import { PostFeed } from "@/components/PostFeed";
import { RequireAuth } from "@/components/SignInPrompt";
import { useAuth } from "@/lib/auth";

export function FavoritesView() {
  return (
    <div className="mx-auto max-w-3xl">
      <div className="mx-auto max-w-read">
        <h1 className="font-serif text-4xl font-semibold tracking-tight">Favourites</h1>
        <p className="mt-2 text-muted">Ideas you&apos;ve hearted, newest first. Your favourites show on your profile.</p>
      </div>
      <div className="mt-8">
        <RequireAuth message="Sign in to keep the ideas you love in one place.">
          <FavoritesList />
        </RequireAuth>
      </div>
    </div>
  );
}

function FavoritesList() {
  const { api, token } = useAuth();
  const load = useCallback(
    (cursor: string | null) => api.myFavorites({ cursor, limit: 10 }),
    [api, token], // eslint-disable-line react-hooks/exhaustive-deps
  );
  return (
    <PostFeed
      load={load}
      empty={
        <p className="panel p-6 text-center text-muted">
          No favourites yet. Tap the ♡ on any idea in{" "}
          <Link href="/" className="link">
            your timeline
          </Link>{" "}
          to keep it here.
        </p>
      }
    />
  );
}
