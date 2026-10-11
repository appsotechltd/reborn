"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { FollowButton } from "@/components/FollowButton";
import { PostFeed } from "@/components/PostFeed";
import { ErrorNote, Loading } from "@/components/SignInPrompt";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { Profile } from "@/lib/types";

export function ProfileView({ handle }: { handle: string }) {
  const { api, token, ready } = useAuth();
  // Reload when the viewer signs in or out: is_following and is_me depend on it.
  const loader = useCallback(() => api.profile(handle), [api, handle, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: profile, error, status, loading, setData } = useLoad(ready ? loader : null);
  const [tab, setTab] = useState<"favorites" | "followers">("favorites");

  if (!ready || loading) return <Loading />;
  if (status === 404) {
    return (
      <div className="mx-auto max-w-read py-12 text-center">
        <h1 className="font-serif text-3xl font-semibold">No one here by that name</h1>
        <p className="mt-2 text-muted">@{handle} doesn&apos;t match any account.</p>
      </div>
    );
  }
  if (error || !profile) return <ErrorNote error={error ?? "Couldn't load this profile."} />;

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mx-auto max-w-read text-center">
        <span
          aria-hidden="true"
          className="mx-auto grid size-16 place-items-center rounded-full bg-accent text-2xl font-bold text-accent-fg"
        >
          {profile.display_name.slice(0, 1).toUpperCase()}
        </span>
        <h1 className="mt-3 font-serif text-3xl font-semibold tracking-tight">{profile.display_name}</h1>
        <p className="text-muted">@{profile.handle}</p>
        {profile.bio ? <p className="mt-3 whitespace-pre-line text-pretty">{profile.bio}</p> : null}
        <p className="mt-3 flex justify-center gap-4 text-sm">
          <span>
            <strong>{profile.followers}</strong> <span className="text-muted">{profile.followers === 1 ? "follower" : "followers"}</span>
          </span>
          {profile.is_me ? (
            <Link href="/following" className="hover:underline">
              <strong>{profile.following}</strong> <span className="text-muted">following</span>
            </Link>
          ) : (
            <span>
              <strong>{profile.following}</strong> <span className="text-muted">following</span>
            </span>
          )}
          <span>
            <strong>{profile.favorites}</strong> <span className="text-muted">{profile.favorites === 1 ? "favourite" : "favourites"}</span>
          </span>
        </p>
        <div className="mt-4 flex justify-center gap-2">
          {profile.is_me ? (
            <Link href="/settings" className="btn btn-small">
              Edit profile
            </Link>
          ) : (
            <FollowButton
              kind="user"
              target={profile.id}
              label={profile.display_name}
              initial={{ followers: profile.followers, is_following: profile.is_following }}
              hideCount
              onChange={(s) => setData((p) => ({ ...(p as Profile), followers: s.followers, is_following: s.is_following }))}
            />
          )}
        </div>
      </header>

      <div role="tablist" aria-label="Profile sections" className="mt-10 flex justify-center gap-1 border-b border-line">
        {(
          [
            ["favorites", "Favourites"],
            ["followers", "Followers"],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            role="tab"
            id={`tab-${id}`}
            aria-selected={tab === id}
            aria-controls={`panel-${id}`}
            className={`-mb-px min-h-11 border-b-2 px-4 ${tab === id ? "border-accent font-semibold" : "border-transparent text-muted hover:text-fg"}`}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className="mt-6">
        {tab === "favorites" ? (
          <ProfileFavorites handle={profile.handle} name={profile.display_name} isMe={profile.is_me} />
        ) : (
          <Followers handle={profile.handle} />
        )}
      </div>
    </div>
  );
}

function ProfileFavorites({ handle, name, isMe }: { handle: string; name: string; isMe: boolean }) {
  const { api, token } = useAuth();
  const load = useCallback(
    (cursor: string | null) => api.userFavorites(handle, { cursor, limit: 10 }),
    [api, handle, token], // eslint-disable-line react-hooks/exhaustive-deps
  );
  return (
    <PostFeed
      load={load}
      empty={
        <p className="panel p-6 text-center text-muted">
          {isMe ? "Ideas you favourite will show up here." : `${name} hasn't favourited any ideas yet.`}
        </p>
      }
    />
  );
}

function Followers({ handle }: { handle: string }) {
  const { api } = useAuth();
  const loader = useCallback(() => api.userFollowers(handle, { limit: 50 }), [api, handle]);
  const { data, error, loading } = useLoad(loader);
  if (loading) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  if (!data?.users.length) return <p className="panel p-6 text-center text-muted">No followers yet.</p>;
  return (
    <ul className="mx-auto max-w-read divide-y divide-line border-y border-line">
      {data.users.map((u) => (
        <li key={u.id} className="py-3">
          <Link href={`/u/${u.handle}`} className="font-semibold hover:underline">
            {u.display_name}
          </Link>{" "}
          <span className="text-muted">@{u.handle}</span>
        </li>
      ))}
    </ul>
  );
}
