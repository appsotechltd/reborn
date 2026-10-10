"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, type ReactNode } from "react";
import { useAuth } from "@/lib/auth";

export function SignInPrompt({ message }: { message?: string }) {
  const pathname = usePathname();
  const next = encodeURIComponent(pathname || "/");
  return (
    <div className="panel mx-auto max-w-read p-6 text-center sm:p-8">
      <h2 className="font-serif text-2xl font-semibold">Sign in to continue</h2>
      <p className="mt-2 text-muted">
        {message ?? "This part of Reborn keeps track of your reading, so it needs an account."}
      </p>
      <div className="mt-5 flex flex-wrap justify-center gap-3">
        <Link href={`/signin?next=${next}`} className="btn btn-primary">
          Sign in
        </Link>
        <Link href={`/register?next=${next}`} className="btn">
          Create an account
        </Link>
      </div>
    </div>
  );
}

export function Loading({ label = "Loading…" }: { label?: string }) {
  return (
    <p role="status" className="py-10 text-center text-muted">
      {label}
    </p>
  );
}

/** Renders children only for signed-in users; otherwise a sign-in prompt. */
export function RequireAuth({ children, message }: { children: ReactNode; message?: string }) {
  const { ready, user } = useAuth();
  if (!ready) return <Loading />;
  if (!user) return <SignInPrompt message={message} />;
  return <>{children}</>;
}

export function ErrorNote({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="mt-3 rounded-lg border border-bad px-3 py-2 text-sm text-bad">
      {error}
    </p>
  );
}

/** Returns a function that sends a signed-out visitor to sign in, then back to this page. */
export function useSignInRedirect() {
  const router = useRouter();
  const pathname = usePathname();
  return useCallback(() => {
    router.push(`/signin?next=${encodeURIComponent(pathname || "/")}`);
  }, [router, pathname]);
}
