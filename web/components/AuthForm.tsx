"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useSyncExternalStore } from "react";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { browserTimezone, clearReferral, isReferralCode, readReferral } from "@/lib/engage";

const noopSubscribe = () => () => {};

/** The topic picker a new account sees straight after sign-up, then on to `next`. */
export function welcomeHref(next: string): string {
  return next && next !== "/" ? `/welcome?next=${encodeURIComponent(next)}` : "/welcome";
}

export function AuthForm({ mode, next, referral }: { mode: "signin" | "register"; next: string; referral?: string }) {
  const { api, signIn } = useAuth();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const register = mode === "register";
  // A code from /register?ref=, else one remembered by /join?ref=.
  const stored = useSyncExternalStore(noopSubscribe, readReferral, () => null);
  const [code, setCode] = useState<string | null>(null);
  const referralCode = code ?? (isReferralCode(referral) ? referral : stored) ?? "";

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (register && password.length < 8) {
      setError("Use at least 8 characters for your password.");
      return;
    }
    setBusy(true);
    try {
      const res = register
        ? await api.register({
            email: email.trim(),
            password,
            display_name: name.trim(),
            timezone: browserTimezone(),
            ...(referralCode.trim() ? { referral_code: referralCode.trim() } : {}),
          })
        : await api.login({ email: email.trim(), password });
      if (register) clearReferral();
      signIn(res.token, res.user);
      // A new account picks its topics first (as in the app), then goes where it was headed.
      router.push(register ? welcomeHref(next) : next);
    } catch (err) {
      setError(
        isApiError(err)
          ? err.status === 401
            ? "That email and password don't match."
            : err.message
          : "Something went wrong. Please try again.",
      );
      setBusy(false);
    }
  }

  const other = register ? "/signin" : "/register";
  const nextQs = next !== "/" ? `?next=${encodeURIComponent(next)}` : "";

  return (
    <div className="mx-auto max-w-sm">
      <h1 className="font-serif text-3xl font-semibold">{register ? "Create your account" : "Welcome back"}</h1>
      <p className="mt-2 text-muted">
        {register
          ? "Save ideas, review them at the right time and ask the guide."
          : "Sign in to your stashes, reviews and quizzes."}
      </p>
      <form onSubmit={submit} className="mt-6 space-y-4" noValidate={false}>
        {register ? (
          <div>
            <label htmlFor="display_name" className="label">
              Name
            </label>
            <input
              id="display_name"
              className="field"
              autoComplete="name"
              required
              maxLength={80}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
        ) : null}
        <div>
          <label htmlFor="email" className="label">
            Email
          </label>
          <input
            id="email"
            type="email"
            className="field"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>
        <div>
          <label htmlFor="password" className="label">
            Password
          </label>
          <input
            id="password"
            type="password"
            className="field"
            autoComplete={register ? "new-password" : "current-password"}
            required
            minLength={register ? 8 : undefined}
            aria-describedby={register ? "password-hint" : undefined}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          {register ? (
            <p id="password-hint" className="hint">
              At least 8 characters.
            </p>
          ) : (
            <p className="mt-2 text-right text-sm">
              <Link href="/forgot-password" className="link">
                Forgot password?
              </Link>
            </p>
          )}
        </div>
        {register ? (
          <div>
            <label htmlFor="referral_code" className="label">
              Invite code <span className="font-normal text-muted">(optional)</span>
            </label>
            <input
              id="referral_code"
              className="field"
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              maxLength={40}
              value={referralCode}
              onChange={(e) => setCode(e.target.value)}
            />
          </div>
        ) : null}
        {error ? (
          <p role="alert" className="rounded-lg border border-bad px-3 py-2 text-sm text-bad">
            {error}
          </p>
        ) : null}
        <button type="submit" className="btn btn-primary w-full" disabled={busy}>
          {busy ? "Please wait…" : register ? "Create account" : "Sign in"}
        </button>
      </form>
      <p className="mt-6 text-center text-sm text-muted">
        {register ? "Already have an account? " : "New to Reborn? "}
        <Link href={`${other}${nextQs}`} className="link">
          {register ? "Sign in" : "Create an account"}
        </Link>
      </p>
    </div>
  );
}
