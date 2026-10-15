"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useState } from "react";
import { BlockMenu } from "@/components/BlockMenu";
import { FollowButton } from "@/components/FollowButton";
import { PremiumBadge } from "@/components/PremiumBadge";
import { PostFeed } from "@/components/PostFeed";
import { ShareMenu } from "@/components/ShareMenu";
import { ErrorNote, Loading, useSignInRedirect } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formatMoney } from "@/lib/social";
import { useLoad } from "@/lib/use-load";
import type { MemberCategory, Profile, UserPlanResponse } from "@/lib/types";

export function ProfileView({ handle }: { handle: string }) {
  const { api, token, ready, user } = useAuth();
  // Reload when the viewer signs in or out: is_following and is_me depend on it.
  const loader = useCallback(() => api.profile(handle), [api, handle, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: profile, error, status, loading, setData } = useLoad(ready ? loader : null);
  const [tab, setTab] = useState<"cards" | "favorites" | "stashes" | "followers">("cards");
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
          <ShareMenu path={`/u/${profile.handle}`} title={`${profile.display_name} on Reborn`} what="profile" label />
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

      <Suspense fallback={null}>
        <SubscribedNote />
      </Suspense>
      <SubscribeBox handle={profile.handle} name={profile.display_name} isMe={profile.is_me} />

      <div role="tablist" aria-label="Profile sections" className="mt-10 flex justify-center gap-1 overflow-x-auto border-b border-line">
        {(
          [
            ["cards", "Cards"],
            ["favorites", "Favourites"],
            ["stashes", "Collections"],
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
            className={`-mb-px min-h-11 shrink-0 border-b-2 px-4 max-sm:px-3 ${tab === id ? "border-accent font-semibold" : "border-transparent text-muted hover:text-fg"}`}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className="mt-6">
        {tab === "cards" ? (
          <ProfileCards handle={profile.handle} name={profile.display_name} isMe={profile.is_me} />
        ) : tab === "favorites" ? (
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

function longDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
}

/** Back from Stripe Checkout (?subscribed=1): the subscription shows once the payment is confirmed. */
function SubscribedNote() {
  const params = useSearchParams();
  if (params.get("subscribed") !== "1") return null;
  return (
    <p role="status" className="panel mx-auto mt-6 max-w-read p-4 text-center">
      Thanks for subscribing. It can take a moment to show here.
    </p>
  );
}

/** The writer's subscription offer: price, pitch, what it opens, and Subscribe or the viewer's subscription. */
function SubscribeBox({ handle, name, isMe }: { handle: string; name: string; isMe: boolean }) {
  const { api, token, user } = useAuth();
  const toSignIn = useSignInRedirect();
  const loader = useCallback(() => api.userPlan(handle), [api, handle, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, setData } = useLoad<UserPlanResponse>(loader);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!data) return null;
  const sub = data.subscription?.active ? data.subscription : null;
  // Not selling subscriptions (any more): someone still subscribed can see until when.
  if ((!data.plan || !data.tier) && !sub) return null;

  async function subscribe() {
    if (!user) return toSignIn();
    setBusy(true);
    setError(null);
    try {
      const { url } = await api.subscribeCheckout(handle);
      window.location.assign(url);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't start the payment. Please try again.");
      setBusy(false);
    }
  }

  async function cancel() {
    if (!window.confirm(`Stop renewing your subscription to ${name}? You keep it until it runs out.`)) return;
    setBusy(true);
    setError(null);
    try {
      const updated = await api.cancelSubscription(handle);
      setData((d) => ({ ...(d as UserPlanResponse), subscription: updated }));
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't cancel the renewal. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section aria-labelledby="subscribe-title" className="panel mx-auto mt-8 max-w-read p-5" data-testid="subscribe-box">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="subscribe-title" className="font-serif text-xl font-semibold">
          {isMe ? "Your subscription offer" : `Subscribe to ${name}`}
        </h2>
        {data.tier ? (
          <p className="font-semibold">
            {formatMoney(data.tier.amount_cents, data.tier.currency)}
            <span className="font-normal text-muted"> a month</span>
          </p>
        ) : null}
      </div>
      {data.plan?.pitch ? <p className="mt-2 whitespace-pre-line text-pretty">{data.plan.pitch}</p> : null}
      <p className="mt-2 text-sm text-muted">
        {data.plan ? `${data.plan.subscribers} ${data.plan.subscribers === 1 ? "subscriber" : "subscribers"}` : null}
        {data.plan && data.locked_cards > 0 ? " · " : null}
        {data.locked_cards > 0
          ? `${data.locked_cards} subscriber-only ${data.locked_cards === 1 ? "card" : "cards"}`
          : null}
      </p>
      {isMe ? (
        <p className="mt-3 text-sm">
          <Link href="/me/earnings" className="link">
            Change it in Earnings
          </Link>
        </p>
      ) : sub ? (
        <div className="mt-3 flex flex-wrap items-center gap-3">
          <p className="font-semibold text-ok">
            Subscribed until {longDate(sub.expires_at)}
          </p>
          {sub.renews ? (
            <button type="button" className="btn btn-small" disabled={busy} onClick={cancel}>
              Cancel renewal
            </button>
          ) : null}
        </div>
      ) : data.providers.stripe ? (
        <button type="button" className="btn btn-primary mt-4" disabled={busy} onClick={subscribe}>
          {busy ? "Opening checkout…" : "Subscribe"}
        </button>
      ) : (
        <p role="status" className="mt-3 rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm">
          Subscriptions on the web are coming soon. You can subscribe in the Reborn app.
        </p>
      )}
      <ErrorNote error={error} />
    </section>
  );
}

/** The member's own cards that the viewer may see, filtered by their categories. */
function ProfileCards({ handle, name, isMe }: { handle: string; name: string; isMe: boolean }) {
  const { api, token } = useAuth();
  const [category, setCategory] = useState("");
  const [categories, setCategories] = useState<MemberCategory[]>([]);
  const load = useCallback(
    async (cursor: string | null) => {
      const res = await api.userCards(handle, { category: category || undefined, cursor, limit: 10 });
      if (res.categories) setCategories(res.categories);
      return res;
    },
    [api, handle, category, token], // eslint-disable-line react-hooks/exhaustive-deps
  );
  return (
    <>
      {isMe ? (
        <p className="mb-4 text-center text-sm">
          <Link href="/me/cards" className="link">
            Manage your cards
          </Link>
        </p>
      ) : null}
      {categories.length ? (
        <div role="group" aria-label="Categories" className="mb-5 flex flex-wrap justify-center gap-2">
          {[{ id: "", name: "All" }, ...categories].map((c) => (
            <button
              key={c.id || "all"}
              type="button"
              aria-pressed={category === c.id}
              className={`chip min-h-9 pointer-coarse:min-h-11 ${category === c.id ? "chip-on" : "hover:text-fg"}`}
              onClick={() => setCategory(c.id)}
            >
              {c.name}
            </button>
          ))}
        </div>
      ) : null}
      <PostFeed
        load={load}
        empty={
          <p className="panel p-6 text-center text-muted">
            {isMe ? (
              <>
                Cards you write show up here.{" "}
                <Link href="/me/cards/new" className="link">
                  Write a card
                </Link>
              </>
            ) : (
              `${name} hasn't shared any cards yet.`
            )}
          </p>
        }
      />
    </>
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
            You have no public collections. Make one public from{" "}
            <Link href="/stashes" className="link">
              your collections
            </Link>
            .
          </>
        ) : (
          `${name} hasn't shared any collections yet.`
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
