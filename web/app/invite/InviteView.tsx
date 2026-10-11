"use client";

import { useCallback, useState } from "react";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { useAuth } from "@/lib/auth";
import { shareTargets } from "@/lib/social";
import { useLoad } from "@/lib/use-load";

export function InviteView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Invite friends</h1>
      <p className="mt-2 text-muted">Share Reborn with people who like big ideas.</p>
      <div className="mt-8">
        <RequireAuth message="Sign in to get your invite link.">
          <Invite />
        </RequireAuth>
      </div>
    </div>
  );
}

function Invite() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.referrals(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad(loader);
  const [copied, setCopied] = useState<"link" | "code" | null>(null);
  const [copyError, setCopyError] = useState<string | null>(null);

  if (loading) return <Loading />;
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load your invite link."} />;

  async function copy(text: string, what: "link" | "code") {
    setCopyError(null);
    try {
      await navigator.clipboard.writeText(text);
      setCopied(what);
      window.setTimeout(() => setCopied(null), 2500);
    } catch {
      setCopyError("Couldn't copy automatically. Select it and copy it yourself.");
    }
  }

  const message = "I've been reading big ideas from great books on Reborn, one minute at a time. Join me:";

  return (
    <div className="space-y-8">
      <div className="panel bg-accent-soft p-5">
        <p className="font-semibold">You both get {data.reward_days} days of Premium</p>
        <p className="mt-1 text-sm text-muted">
          When a friend joins with your link and reads on three different days, you each get {data.reward_days} free days of
          Premium.
        </p>
      </div>

      <div>
        <label htmlFor="invite-link" className="label">
          Your invite link
        </label>
        <div className="flex gap-2">
          <input id="invite-link" className="field text-sm" readOnly value={data.link} onFocus={(e) => e.currentTarget.select()} />
          <button type="button" className="btn btn-primary shrink-0" onClick={() => copy(data.link, "link")}>
            {copied === "link" ? "Copied ✓" : "Copy link"}
          </button>
        </div>
        <p className="hint">
          Or share your code:{" "}
          <button type="button" className="font-mono font-semibold text-fg hover:underline" onClick={() => copy(data.code, "code")}>
            {data.code}
          </button>
          {copied === "code" ? " · copied ✓" : ""}
        </p>
        <p role="status" className="sr-only">
          {copied ? `${copied === "link" ? "Link" : "Code"} copied` : ""}
        </p>
        <ErrorNote error={copyError} />
      </div>

      <div>
        <h2 className="label">Share</h2>
        <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {shareTargets(data.link, message).map((t) => (
            <li key={t.channel}>
              <a
                href={t.href}
                target={t.channel === "email" ? undefined : "_blank"}
                rel="noopener noreferrer"
                className="btn btn-small w-full"
              >
                {t.label}
                {t.channel !== "email" ? <span className="sr-only"> (opens in a new tab)</span> : null}
              </a>
            </li>
          ))}
        </ul>
      </div>

      <dl className="grid grid-cols-2 gap-4">
        <div className="panel p-5 text-center">
          <dt className="text-sm text-muted">Friends invited</dt>
          <dd className="mt-1 text-3xl font-semibold">{data.invited}</dd>
        </div>
        <div className="panel p-5 text-center">
          <dt className="text-sm text-muted">Rewards earned</dt>
          <dd className="mt-1 text-3xl font-semibold">{data.rewarded}</dd>
        </div>
      </dl>
    </div>
  );
}
