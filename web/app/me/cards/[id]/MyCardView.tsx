"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { CardView } from "@/components/CardView";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { VisibilityBadge } from "@/components/VisibilityBadge";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { Card } from "@/lib/types";
import { CardEditor } from "../CardEditor";
import { CardStudio } from "./CardStudio";

export function MyCardView({ id }: { id: string }) {
  return (
    <div className="mx-auto max-w-read">
      <p>
        <Link href="/me/cards" className="link text-sm">
          ← My cards
        </Link>
      </p>
      <div className="mt-4">
        <RequireAuth message="Sign in to edit your cards.">
          <MyCard id={id} />
        </RequireAuth>
      </div>
    </div>
  );
}

function MyCard({ id }: { id: string }) {
  const { api, token } = useAuth();
  const router = useRouter();
  const loader = useCallback(() => api.myCard(id), [api, id, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: card, error, status, loading, setData } = useLoad<Card>(loader);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  if (loading) return <Loading />;
  if (status === 404) {
    return (
      <div>
        <h1 className="font-serif text-3xl font-semibold">Card not found</h1>
        <p className="mt-2 text-muted">It may have been deleted.</p>
      </div>
    );
  }
  if (error || !card) return <ErrorNote error={error ?? "Couldn't load this card."} />;

  const update = (c: Card) => setData(() => c);
  const shared = card.visibility !== "private" && card.visibility !== "hidden";

  async function remove() {
    if (!window.confirm("Delete this card? This can't be undone.")) return;
    setBusy(true);
    setActionError(null);
    try {
      await api.deleteMyCard(id);
      router.push("/me/cards");
    } catch (err) {
      setActionError(isApiError(err) ? err.message : "Couldn't delete the card.");
      setBusy(false);
    }
  }

  return (
    <>
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="font-serif text-4xl font-semibold tracking-tight">Edit card</h1>
        <VisibilityBadge visibility={card.visibility} />
      </header>
      {shared ? (
        <p className="mt-2 text-sm">
          <Link href={`/ideas/${encodeURIComponent(card.id)}`} className="link">
            View the post
          </Link>
        </p>
      ) : null}

      <div className="mt-6">
        <CardEditor card={card} onSaved={update} />
      </div>

      <CardStudio card={card} onCard={update} />

      <section aria-labelledby="preview-title" className="mt-12">
        <h2 id="preview-title" className="eyebrow">
          Preview
        </h2>
        <div className="panel mt-3 px-5 py-6 sm:px-8 sm:py-8">
          <CardView card={card} headingLevel="h2" />
        </div>
      </section>

      <div className="mt-10 border-t border-line pt-6">
        <button type="button" className="btn text-bad" onClick={remove} disabled={busy}>
          Delete card
        </button>
        <ErrorNote error={actionError} />
      </div>
    </>
  );
}
