"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { ErrorNote, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { TOPICS } from "@/lib/content";
import type { User } from "@/lib/types";

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
    setBusy(true);
    try {
      const updated = await api.updateMe({
        display_name: name.trim(),
        topics,
        bio: bio.trim(),
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
