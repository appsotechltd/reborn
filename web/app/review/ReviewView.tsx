"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { CardView } from "@/components/CardView";
import { Quiz } from "@/components/Quiz";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";
import type { Grade, ReviewItem } from "@/lib/types";

const GRADES: { grade: Grade; label: string; hint: string }[] = [
  { grade: "again", label: "Again", hint: "I forgot it" },
  { grade: "hard", label: "Hard", hint: "Barely remembered" },
  { grade: "good", label: "Good", hint: "Remembered it" },
  { grade: "easy", label: "Easy", hint: "Knew it instantly" },
];

export function ReviewView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Review</h1>
      <p className="mt-2 text-muted">
        Ideas come back just before you&apos;d forget them. Recall, then grade how well you remembered.
      </p>
      <div className="mt-8">
        <RequireAuth message="Sign in to review the ideas you've saved.">
          <ReviewSession />
        </RequireAuth>
      </div>
    </div>
  );
}

function ReviewSession() {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.due(20), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading, reload } = useLoad(loader);
  const [index, setIndex] = useState(0);
  const [revealed, setRevealed] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [gradeError, setGradeError] = useState<string | null>(null);
  const [done, setDone] = useState(0);

  if (loading) return <Loading label="Finding ideas due for review…" />;
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load your review."} />;

  const items: ReviewItem[] = data.items;
  const item = items[index];

  if (!item) {
    return (
      <div className="panel p-6 text-center">
        <h2 className="font-serif text-2xl font-semibold">
          {done ? `Nice work: ${done} ${done === 1 ? "idea" : "ideas"} reviewed` : "Nothing due right now"}
        </h2>
        <p className="mt-2 text-muted">
          {done
            ? "Come back later and they'll be waiting at the right moment."
            : "Save ideas you want to keep and they'll show up here when it's time to recall them."}
        </p>
        <div className="mt-5 flex flex-wrap justify-center gap-3">
          {done ? (
            <button
              type="button"
              className="btn"
              onClick={() => {
                setIndex(0);
                setDone(0);
                reload();
              }}
            >
              Check for more
            </button>
          ) : null}
          <Link href="/quiz" className="btn">
            Take a quiz
          </Link>
          <Link href="/" className="btn btn-primary">
            Find new ideas
          </Link>
        </div>
      </div>
    );
  }

  const card = item.card;
  const showCard = !card.quiz || revealed === card.id;

  async function grade(g: Grade) {
    setBusy(true);
    setGradeError(null);
    try {
      await api.grade(card.id, g);
      setDone((d) => d + 1);
      setIndex((i) => i + 1);
      setRevealed(null);
      window.scrollTo({ top: 0 });
    } catch (err) {
      setGradeError(isApiError(err) ? err.message : "Couldn't save your grade.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <p className="text-sm text-muted" aria-live="polite">
        Idea {index + 1} of {items.length}
        {data.due_count > items.length ? ` (${data.due_count} due in total)` : ""}
      </p>

      {!showCard && card.quiz ? (
        <div key={`quiz-${card.id}`}>
          <h2 className="mt-4 font-serif text-2xl font-semibold">Recall first</h2>
          <Quiz quiz={card.quiz} title="Do you remember?" />
          <button type="button" className="btn btn-primary mt-4" onClick={() => setRevealed(card.id)}>
            Show the idea
          </button>
        </div>
      ) : (
        <div className="mt-4" key={`card-${card.id}`}>
          <CardView card={card} headingLevel="h2" />
          <section aria-labelledby="grade-title" className="panel mt-8 p-5">
            <h2 id="grade-title" className="font-semibold">
              How well did you remember it?
            </h2>
            <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
              {GRADES.map((g) => (
                <button
                  key={g.grade}
                  type="button"
                  className={`btn flex-col ${g.grade === "good" ? "btn-primary" : ""}`}
                  onClick={() => grade(g.grade)}
                  disabled={busy}
                >
                  <span>{g.label}</span>
                  <span className="text-xs font-normal opacity-80">{g.hint}</span>
                </button>
              ))}
            </div>
            <ErrorNote error={gradeError} />
          </section>
        </div>
      )}
    </div>
  );
}
