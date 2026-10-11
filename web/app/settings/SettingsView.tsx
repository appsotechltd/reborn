"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { ErrorNote, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { TOPICS } from "@/lib/content";
import { browserTimezone, timezones } from "@/lib/engage";
import { useLoad } from "@/lib/use-load";
import type { BlockedUser, NotifyKind, User } from "@/lib/types";

export function SettingsView() {
  const { user } = useAuth();
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Settings</h1>
      <div className="mt-8">
        <RequireAuth>
          {user ? (
            <>
              <SettingsForm key={user.id} user={user} />
              <BlockedList />
              <DeleteAccount />
            </>
          ) : null}
        </RequireAuth>
      </div>
    </div>
  );
}

const HANDLE_RE = /^[a-z0-9_]{3,30}$/;

function SettingsForm({ user }: { user: User }) {
  const { api, setUser } = useAuth();
  const [name, setName] = useState(user.display_name);
  const [handle, setHandle] = useState(user.handle ?? "");
  const [bio, setBio] = useState(user.bio ?? "");
  const [handleError, setHandleError] = useState<string | null>(null);
  const [topics, setTopics] = useState<string[]>(user.topics ?? []);
  const [goal, setGoal] = useState(String(user.daily_goal ?? 3));
  // Default to the browser's zone when the account still has the server default.
  const [timezone, setTimezone] = useState(
    () => (user.timezone && user.timezone !== "UTC" ? user.timezone : browserTimezone()) ?? user.timezone ?? "UTC",
  );
  const [notify, setNotify] = useState<Record<NotifyKind, boolean>>({
    daily: user.notify?.daily ?? true,
    replies: user.notify?.replies ?? true,
    follows: user.notify?.follows ?? true,
    circles: user.notify?.circles ?? true,
  });
  const [zones] = useState(() => {
    const all = timezones();
    return all.includes(timezone) ? all : [timezone, ...all];
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setHandleError(null);
    setSaved(false);
    const h = handle.trim().toLowerCase();
    if (h && !HANDLE_RE.test(h)) {
      setHandleError("Use 3-30 lowercase letters, numbers or underscores.");
      return;
    }
    const dailyGoal = Number(goal);
    if (!Number.isInteger(dailyGoal) || dailyGoal < 1 || dailyGoal > 50) {
      setError("Set a daily goal between 1 and 50 ideas.");
      return;
    }
    setBusy(true);
    try {
      const updated = await api.updateMe({
        display_name: name.trim(),
        topics,
        bio: bio.trim(),
        daily_goal: dailyGoal,
        notify,
        ...(timezone && timezone !== user.timezone ? { timezone } : {}),
        ...(h && h !== user.handle ? { handle: h } : {}),
      });
      setUser(updated);
      setHandle(updated.handle ?? h);
      setSaved(true);
    } catch (err) {
      if (isApiError(err) && err.code === "handle_taken") setHandleError(`@${h} is taken. Try another handle.`);
      else setError(isApiError(err) ? err.message : "Couldn't save your settings.");
    } finally {
      setBusy(false);
    }
  }

  const toggle = (slug: string) =>
    setTopics((t) => (t.includes(slug) ? t.filter((s) => s !== slug) : [...t, slug]));

  return (
    <form onSubmit={save} className="space-y-8">
      <div>
        <label htmlFor="display-name" className="label">Display name</label>
        <input id="display-name" className="field" required maxLength={80} value={name} onChange={(e) => setName(e.target.value)} />
        <p className="hint">Signed in as {user.email}{user.role === "moderator" ? " · moderator" : ""}</p>
      </div>
      <div>
        <label htmlFor="handle" className="label">Handle</label>
        <div className="flex items-center gap-2">
          <span aria-hidden="true" className="text-muted">@</span>
          <input
            id="handle"
            className="field"
            autoComplete="username"
            autoCapitalize="none"
            spellCheck={false}
            minLength={3}
            maxLength={30}
            pattern="[a-z0-9_]{3,30}"
            aria-describedby="handle-hint"
            aria-invalid={handleError ? true : undefined}
            value={handle}
            onChange={(e) => setHandle(e.target.value.toLowerCase())}
          />
        </div>
        <p id="handle-hint" className="hint">
          3-30 lowercase letters, numbers or underscores. Your profile is at{" "}
          {user.handle ? <Link href={`/u/${user.handle}`} className="link">/u/{user.handle}</Link> : "/u/your-handle"}.
        </p>
        {handleError ? <p role="alert" className="mt-1 text-sm text-bad">{handleError}</p> : null}
      </div>
      <div>
        <label htmlFor="bio" className="label">Bio</label>
        <textarea
          id="bio"
          className="field min-h-24"
          maxLength={300}
          aria-describedby="bio-hint"
          value={bio}
          onChange={(e) => setBio(e.target.value)}
        />
        <p id="bio-hint" className="hint">Shown on your profile. {bio.length}/300</p>
      </div>
      <div className="grid gap-6 sm:grid-cols-2">
        <div id="goal" className="scroll-mt-24">
          <label htmlFor="daily-goal" className="label">Daily goal</label>
          <input
            id="daily-goal"
            type="number"
            inputMode="numeric"
            min={1}
            max={50}
            className="field"
            aria-describedby="goal-hint"
            value={goal}
            onChange={(e) => setGoal(e.target.value)}
          />
          <p id="goal-hint" className="hint">Ideas to read each day to keep your streak (1-50).</p>
        </div>
        <div>
          <label htmlFor="timezone" className="label">Timezone</label>
          {zones.length > 1 ? (
            <select id="timezone" className="field" value={timezone} onChange={(e) => setTimezone(e.target.value)} aria-describedby="tz-hint">
              {zones.map((z) => (
                <option key={z} value={z}>{z.replace(/_/g, " ")}</option>
              ))}
            </select>
          ) : (
            <input id="timezone" className="field" value={timezone} onChange={(e) => setTimezone(e.target.value)} aria-describedby="tz-hint" />
          )}
          <p id="tz-hint" className="hint">Your day, streak and daily reminder follow this.</p>
        </div>
      </div>
      <fieldset>
        <legend className="label">Notifications</legend>
        <p className="hint mb-3 mt-0">Choose which push notifications you get on your phone.</p>
        <div className="grid gap-2 sm:grid-cols-2">
          {(
            [
              ["daily", "Daily idea"],
              ["replies", "Replies to my comments"],
              ["follows", "New followers"],
              ["circles", "Book circle messages"],
            ] as const
          ).map(([kind, label]) => (
            <label key={kind} className="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border border-line px-3 py-2 hover:bg-surface-2">
              <input
                type="checkbox"
                className="size-4"
                checked={notify[kind]}
                onChange={(e) => setNotify((n) => ({ ...n, [kind]: e.target.checked }))}
              />
              {label}
            </label>
          ))}
        </div>
      </fieldset>
      <fieldset>
        <legend className="label">Your topics</legend>
        <p className="hint mb-3 mt-0">Your feed favours these. Leave them all off to see everything.</p>
        <div className="grid gap-2 sm:grid-cols-2">
          {TOPICS.map((t) => (
            <label
              key={t.slug}
              className={`flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border px-3 py-2 ${
                topics.includes(t.slug) ? "border-accent bg-accent-soft" : "border-line hover:bg-surface-2"
              }`}
            >
              <input type="checkbox" className="size-4" checked={topics.includes(t.slug)} onChange={() => toggle(t.slug)} />
              {t.name}
            </label>
          ))}
        </div>
      </fieldset>
      <ErrorNote error={error} />
      {saved ? <p role="status" className="text-ok">Saved.</p> : null}
      <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
        {busy ? "Saving…" : "Save settings"}
      </button>
    </form>
  );
}

function BlockedList() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.blocks().then((r) => r.blocks), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, setData } = useLoad<BlockedUser[]>(loader);
  const [busy, setBusy] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  async function undo(b: BlockedUser) {
    setBusy(b.id);
    setActionError(null);
    try {
      await api.setBlock(b.id, null);
      setData((prev) => (prev ?? []).filter((x) => x.id !== b.id));
    } catch (err) {
      setActionError(isApiError(err) ? err.message : "Couldn't undo that.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <section aria-labelledby="blocked-title" className="mt-16">
      <h2 id="blocked-title" className="font-serif text-xl font-semibold">Blocked &amp; muted</h2>
      <p className="mt-1 text-sm text-muted">
        Muted people are hidden from you. Blocked people are hidden both ways and can&apos;t follow you.
      </p>
      {loading ? (
        <p role="status" className="mt-3 text-muted">Loading…</p>
      ) : error ? (
        <ErrorNote error={error} />
      ) : !data?.length ? (
        <p className="mt-3 text-muted">You haven&apos;t blocked or muted anyone.</p>
      ) : (
        <ul className="mt-3 divide-y divide-line border-y border-line">
          {data.map((b) => (
            <li key={b.id} className="flex items-center justify-between gap-3 py-3">
              <span className="min-w-0">
                <Link href={`/u/${b.handle}`} className="font-semibold hover:underline">{b.display_name}</Link>{" "}
                <span className="text-muted">@{b.handle} · {b.kind === "block" ? "Blocked" : "Muted"}</span>
              </span>
              <button type="button" className="btn btn-small shrink-0" disabled={busy !== null} onClick={() => undo(b)}>
                {busy === b.id ? "…" : b.kind === "block" ? "Unblock" : "Unmute"}
                <span className="sr-only"> {b.display_name}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
      <ErrorNote error={actionError} />
    </section>
  );
}

const CONFIRM_WORD = "DELETE";

function DeleteAccount() {
  const { api, signOut } = useAuth();
  const router = useRouter();
  const [typed, setTyped] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove(e: React.FormEvent) {
    e.preventDefault();
    if (typed !== CONFIRM_WORD) return;
    setBusy(true);
    setError(null);
    try {
      await api.deleteMe();
      signOut();
      router.push("/");
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't delete your account.");
      setBusy(false);
    }
  }

  return (
    <section aria-labelledby="delete-title" className="mt-16 rounded-xl border border-bad p-5">
      <h2 id="delete-title" className="font-serif text-xl font-semibold text-bad">Delete account</h2>
      <p className="mt-2 text-sm">
        This permanently deletes your account and everything it owns: stashes, reviews, favourites, follows, reactions
        and comments. It can&apos;t be undone.
      </p>
      <form onSubmit={remove} className="mt-4">
        <label htmlFor="delete-confirm" className="label">
          Type <strong>{CONFIRM_WORD}</strong> to confirm
        </label>
        <input
          id="delete-confirm"
          className="field"
          autoComplete="off"
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
        />
        <ErrorNote error={error} />
        <button type="submit" className="btn mt-3 border-bad text-bad" disabled={busy || typed !== CONFIRM_WORD}>
          {busy ? "Deleting…" : "Delete my account"}
        </button>
      </form>
    </section>
  );
}
