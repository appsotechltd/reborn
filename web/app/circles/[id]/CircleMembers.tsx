"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ErrorNote } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { CircleMember } from "@/lib/types";

/** A circle's members, owner first. Bump `version` to reload (after joining or leaving). */
export function CircleMembers({ circleId, version = 0 }: { circleId: string; version?: number }) {
  const { api, token } = useAuth();
  // Keeps showing the current list while a refresh (after join or leave) loads.
  const [state, setState] = useState<{ key: string; members: CircleMember[] | null; error: string | null }>({
    key: "",
    members: null,
    error: null,
  });
  const key = `${circleId}:${version}:${token ?? ""}`;

  useEffect(() => {
    let cancelled = false;
    api
      .circleMembers(circleId)
      .then((r) => {
        if (!cancelled) setState({ key, members: r.members, error: null });
      })
      .catch((err) => {
        if (!cancelled) setState((s) => ({ ...s, key, error: isApiError(err) ? err.message : "Couldn't load the members." }));
      });
    return () => {
      cancelled = true;
    };
  }, [api, circleId, key]);

  const data = state.members;
  const error = state.error;
  const loading = state.key !== key;

  return (
    <section aria-labelledby="members-title" className="mt-8">
      <h2 id="members-title" className="font-serif text-xl font-semibold">
        Members{data ? <span className="text-muted"> ({data.length})</span> : null}
      </h2>
      {error ? (
        <ErrorNote error={error} />
      ) : loading && !data ? (
        <p role="status" className="mt-2 text-sm text-muted">
          Loading members…
        </p>
      ) : (
        <ul className="mt-3 flex flex-wrap gap-2" aria-busy={loading}>
          {(data ?? []).map((m) => (
            <li key={m.id}>
              <Link href={`/u/${m.handle}`} className="chip min-h-8 gap-1 hover:text-fg">
                {m.display_name}
                {m.role === "owner" ? (
                  <span className="font-semibold text-accent">
                    <span aria-hidden="true"> ★</span> owner
                  </span>
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
