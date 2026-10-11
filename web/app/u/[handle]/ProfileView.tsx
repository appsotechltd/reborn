"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { BlockMenu } from "@/components/BlockMenu";
import { FollowButton } from "@/components/FollowButton";
import { PremiumBadge } from "@/components/PremiumBadge";
import { PostFeed } from "@/components/PostFeed";
import { ErrorNote, Loading } from "@/components/SignInPrompt";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { Profile } from "@/lib/types";

export function ProfileView({ handle }: { handle: string }) {
  const { api, token, ready, user } = useAuth();
  // Reload when the viewer signs in or out: is_following and is_me depend on it.
  const loader = useCallback(() => api.profile(handle), [api, handle, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: profile, error, status, loading, setData } = useLoad(ready ? loader : null);
  const [tab, setTab] = useState<"favorites" | "stashes" | "followers">("favorites");
  const [blocked, setBlocked] = useState<string | null>(null);

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
          className="mx-auto grid size-16 place-items-center rounded-full bg-oxblood text-2xl font-bold text-oxblood-fg"
        >
          {profile.display_name.slice(0, 1).toUpperCase()}
        </span>
        <h1 className="mt-3 font-serif text-3xl font-semibold tracking-tight">
          {profile.display_name}
          {profile.is_me && user?.premium ? <PremiumBadge className="ml-2 align-middle" /> : null}
        </h1>
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
          {!profile.is_me ? (
            <BlockMenu
              userId={profile.id}
              name={profile.display_name}
              onChange={(kind) =>
                setBlocked(
                  kind === "block"
                    ? `You blocked ${profile.display_name}. You won't see each other's comments or messages.`
                    : kind === "mute"
                      ? `You muted ${profile.display_name}. Their comments and messages are hidden from you.`
                      : null,
                )
              }
            />
          ) : null}
        </div>
        {blocked ? (
          <p role="status" className="mt-3 text-sm text-muted">
            {blocked} Undo from the menu or in{" "}
            <Link href="/settings" className="link">
              Settings
            </Link>
            .
          </p>
        ) : null}
      </header>

      <div role="tablist" aria-label="Profile sections" className="mt-10 flex justify-center gap-1 border-b border-line">
        {(
          [
            ["favorites", "Favourites"],
            ["stashes", "Stashes"],
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
        ) : tab === "stashes" ? (
          <ProfileStashes handle={profile.handle} name={profile.display_name} isMe={profile.is_me} />
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

function ProfileStashes({ handle, name, isMe }: { handle: string; name: string; isMe: boolean }) {
  const { api } = useAuth();
  const loader = useCallback(() => api.userStashes(handle).then((r) => r.stashes), [api, handle]);
  const { data, error, loading } = useLoad(loader);
  if (loading) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  if (!data?.length) {
    return (
      <p className="panel p-6 text-center text-muted">
        {isMe ? (
          <>
            You have no public stashes. Make one public from{" "}
            <Link href="/stashes" className="link">
              your stashes
            </Link>
            .
          </>
        ) : (
          `${name} hasn't shared any stashes yet.`
        )}
      </p>
    );
  }
  return (
    <ul className="grid gap-4 sm:grid-cols-2">
      {data.map((s) => (
        <li key={s.id} className="panel relative p-5 hover:border-accent">
          <h3 className="font-serif text-xl font-semibold">
            <Link href={`/s/${s.id}`} className="after:absolute after:inset-0 hover:underline">
              {s.name}
            </Link>
          </h3>
          {s.description ? <p className="mt-1 text-sm text-muted">{s.description}</p> : null}
          <p className="mt-2 text-xs text-muted">
            {s.card_count} {s.card_count === 1 ? "idea" : "ideas"}
          </p>
        </li>
      ))}
    </ul>
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
