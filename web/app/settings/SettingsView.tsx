"use client";

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
        <RequireAuth>{user ? <SettingsForm key={user.id} user={user} /> : null}</RequireAuth>
      </div>
    </div>
  );
}

function SettingsForm({ user }: { user: User }) {
  const { api, setUser } = useAuth();
  const [name, setName] = useState(user.display_name);
  const [topics, setTopics] = useState<string[]>(user.topics ?? []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      const updated = await api.updateMe({ display_name: name.trim(), topics });
      setUser(updated);
      setSaved(true);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't save your settings.");
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
