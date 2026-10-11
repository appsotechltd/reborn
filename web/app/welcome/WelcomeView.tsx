"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { ErrorNote, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { TOPICS } from "@/lib/content";
import type { User } from "@/lib/types";

/** Below this many topics the picker suggests a few more, as a hint only. */
export const SUGGESTED_TOPICS = 3;

export function WelcomeView({ next, onboarding }: { next: string; onboarding: boolean }) {
  const { user } = useAuth();
  return (
    <div className="mx-auto max-w-read">
      <RequireAuth message="Sign in to choose the topics for your feed.">
        {user ? <TopicPicker key={user.id} user={user} next={next} onboarding={onboarding} /> : null}
      </RequireAuth>
    </div>
  );
}

/**
 * Pick the topics the feed favours, saved to the account (PATCH /v1/me topics), the same
 * call the app makes. Picking none means "show me everything".
 */
export function TopicPicker({ user, next, onboarding }: { user: User; next: string; onboarding: boolean }) {
  const { api, setUser } = useAuth();
  const router = useRouter();
  const [selected, setSelected] = useState<string[]>(user.topics ?? []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = (slug: string) =>
    setSelected((s) => (s.includes(slug) ? s.filter((x) => x !== slug) : [...s, slug]));

  async function save() {
    setBusy(true);
    setError(null);
    try {
      setUser(await api.updateMe({ topics: selected }));
      router.push(next);
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't save your topics. Please try again.");
      setBusy(false);
    }
  }

  const count = selected.length;
  return (
    <section aria-labelledby="picker-title" className={onboarding ? "pt-4 sm:pt-8" : ""}>
      {onboarding ? (
        <>
          <p className="eyebrow">Step 2 of 2</p>
          <h1 id="picker-title" className="mt-1 font-serif text-3xl font-semibold tracking-tight sm:text-4xl">
            Welcome to Reborn
          </h1>
          <p className="mt-2 text-lg text-muted text-pretty">
            Big ideas from great books, one minute at a time. What would you like to grow in?
          </p>
        </>
      ) : (
        <>
          <h1 id="picker-title" className="font-serif text-3xl font-semibold tracking-tight sm:text-4xl">
            Your topics
          </h1>
          <p className="mt-2 text-lg text-muted">Pick the topics for your feed.</p>
        </>
      )}
      <p id="picker-hint" className="mt-4 text-sm text-muted" role="status">
        {count === 0
          ? `Pick ${SUGGESTED_TOPICS} or more for a varied feed, or none to see everything.`
          : count < SUGGESTED_TOPICS
            ? `${count} picked. A few more make a more varied feed.`
            : `${count} picked.`}
      </p>
      <div role="group" aria-labelledby="picker-title" aria-describedby="picker-hint" className="mt-4 flex flex-wrap gap-2">
        {TOPICS.map((t) => {
          const on = selected.includes(t.slug);
          return (
            <button
              key={t.slug}
              type="button"
              aria-pressed={on}
              onClick={() => toggle(t.slug)}
              className={`chip min-h-11 px-4 text-[0.9375rem] ${on ? "chip-on" : "hover:text-fg"}`}
            >
              {on ? (
                <svg aria-hidden="true" viewBox="0 0 12 12" className="-ml-1 mr-1.5 size-3 fill-none stroke-current" strokeWidth="2">
                  <path d="M2 6.5l2.5 2.5L10 3.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              ) : null}
              {t.name}
            </button>
          );
        })}
      </div>
      <ErrorNote error={error} />
      <div className="sticky bottom-0 mt-8 flex items-center gap-3 border-t border-line bg-bg py-4 max-md:bottom-[var(--tabbar-h,0px)]">
        {onboarding ? (
          <Link href={next} className="btn btn-ghost">
            Skip
          </Link>
        ) : (
          <Link href={next} className="btn btn-ghost">
            Cancel
          </Link>
        )}
        <button type="button" className="btn btn-primary ml-auto" disabled={busy} onClick={save}>
          {busy ? "Saving…" : count === 0 ? "Show me everything" : `Continue with ${count}`}
        </button>
      </div>
    </section>
  );
}
