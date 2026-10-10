"use client";

import Link from "next/link";
import { useState } from "react";
import { ErrorNote } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";

export function ForgotPasswordForm() {
  const { api } = useAuth();
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.forgotPassword(email.trim());
      setSent(true);
    } catch (err) {
      // Only network/server trouble lands here: the API answers 202 whether or not the account exists.
      setError(isApiError(err) ? err.message : "Something went wrong. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-sm">
      <h1 className="font-serif text-3xl font-semibold">Forgot your password?</h1>
      {sent ? (
        <div role="status" className="mt-6 rounded-lg border border-ok px-4 py-3">
          <p className="font-semibold">If an account exists, we&apos;ve emailed a link.</p>
          <p className="mt-1 text-sm text-muted">
            It works once, for an hour. Check your spam folder if it doesn&apos;t arrive in a few minutes.
          </p>
        </div>
      ) : (
        <>
          <p className="mt-2 text-muted">Enter your email and we&apos;ll send you a link to choose a new password.</p>
          <form onSubmit={submit} className="mt-6 space-y-4">
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
            <ErrorNote error={error} />
            <button type="submit" className="btn btn-primary w-full" disabled={busy || !email.trim()}>
              {busy ? "Please wait…" : "Email me a link"}
            </button>
          </form>
        </>
      )}
      <p className="mt-6 text-center text-sm text-muted">
        Remembered it?{" "}
        <Link href="/signin" className="link">
          Sign in
        </Link>
      </p>
    </div>
  );
}
