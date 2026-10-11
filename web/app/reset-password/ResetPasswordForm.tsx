"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { ErrorNote } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";

export function ResetPasswordForm({ token }: { token: string }) {
  const { api, signIn } = useAuth();
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expired, setExpired] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (password.length < 8) return setError("Use at least 8 characters for your password.");
    if (password !== confirm) return setError("The two passwords don't match.");
    setBusy(true);
    try {
      const res = await api.resetPassword({ token, password });
      signIn(res.token, res.user);
      router.push("/");
    } catch (err) {
      if (isApiError(err) && err.code === "invalid_token") setExpired(true);
      else setError(isApiError(err) ? err.message : "Something went wrong. Please try again.");
      setBusy(false);
    }
  }

  if (!token || expired) {
    return (
      <div className="mx-auto max-w-sm text-center">
        <h1 className="font-serif text-3xl font-semibold">This link has expired</h1>
        <p className="mt-2 text-muted">Reset links work once, for an hour. Ask for a new one and we&apos;ll email it.</p>
        <Link href="/forgot-password" className="btn btn-primary mt-6">
          Send a new link
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-sm">
      <h1 className="font-serif text-3xl font-semibold">Choose a new password</h1>
      <form onSubmit={submit} className="mt-6 space-y-4">
        <div>
          <label htmlFor="password" className="label">
            New password
          </label>
          <input
            id="password"
            type="password"
            className="field"
            autoComplete="new-password"
            required
            minLength={8}
            aria-describedby="password-hint"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <p id="password-hint" className="hint">
            At least 8 characters.
          </p>
        </div>
        <div>
          <label htmlFor="confirm" className="label">
            Confirm new password
          </label>
          <input
            id="confirm"
            type="password"
            className="field"
            autoComplete="new-password"
            required
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
          />
        </div>
        <ErrorNote error={error} />
        <button type="submit" className="btn btn-primary w-full" disabled={busy}>
          {busy ? "Please wait…" : "Save and sign in"}
        </button>
      </form>
    </div>
  );
}
