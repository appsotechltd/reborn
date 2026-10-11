"use client";

import Link from "next/link";
import { useEffect } from "react";
import { useAuth } from "@/lib/auth";
import { isReferralCode, saveReferral } from "@/lib/engage";

/** Landing page for invite links: remembers the code so sign-up can send it. */
export function JoinView({ code }: { code: string }) {
  const { ready, user } = useAuth();
  const valid = isReferralCode(code);

  useEffect(() => {
    if (valid) saveReferral(code);
  }, [valid, code]);

  const register = valid ? `/register?ref=${encodeURIComponent(code)}` : "/register";
  return (
    <div className="mx-auto max-w-read text-center">
      <p className="eyebrow">You&apos;re invited</p>
      <h1 className="mt-2 font-serif text-4xl font-semibold tracking-tight text-balance">
        Big ideas from great books, one minute at a time.
      </h1>
      <p className="mt-4 text-lg text-muted text-pretty">
        A friend thinks you&apos;ll like Reborn: short idea cards from classic books and open sources, each with one
        thing to try today and a credit to where it came from.
      </p>
      {valid ? (
        <p className="mt-4 text-sm text-muted">
          Join with this invite and you&apos;ll both get free Premium days once you read your first idea.
        </p>
      ) : null}
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        {ready && user ? (
          <Link href="/" className="btn btn-primary">
            You&apos;re already signed in, go to your timeline
          </Link>
        ) : (
          <>
            <Link href={register} className="btn btn-primary">
              Create your free account
            </Link>
            <Link href="/" className="btn">
              Look around first
            </Link>
          </>
        )}
      </div>
    </div>
  );
}
