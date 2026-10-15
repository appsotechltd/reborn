"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { Quiz } from "@/components/Quiz";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { TOPICS } from "@/lib/content";
import { useAuth } from "@/lib/auth";
import { useLoad } from "@/lib/use-load";

export function QuizView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Quiz</h1>
      <p className="mt-2 text-muted">
        Five quick questions, favouring ideas you&apos;ve saved. Right answers push an idea further out in your
        review; wrong ones bring it back soon.
      </p>
      <div className="mt-8">
        <RequireAuth message="Sign in to quiz yourself and track what you remember.">
          <QuizSession />
        </RequireAuth>
      </div>
    </div>
  );
}

function QuizSession() {
  const { api, token } = useAuth();
  const [topic, setTopic] = useState("");
  const [round, setRound] = useState(0);
  const loader = useCallback(
    () => api.quiz({ topic: topic || undefined, limit: 5 }).then((r) => r.cards),
    [api, topic, round, token], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const { data: cards, error, loading } = useLoad(loader);
  const [index, setIndex] = useState(0);
  const [answered, setAnswered] = useState<string | null>(null);
  const [score, setScore] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);

  function restart(nextTopic = topic) {
    setTopic(nextTopic);
    setRound((r) => r + 1);
    setIndex(0);
    setAnswered(null);
    setScore(0);
  }

  const picker = (
    <div className="mb-6 flex flex-wrap items-end gap-3">
      <div>
        <label htmlFor="quiz-topic" className="label">
          Topic
        </label>
        <select id="quiz-topic" className="field" value={topic} onChange={(e) => restart(e.target.value)}>
          <option value="">Any topic</option>
          {TOPICS.map((t) => (
            <option key={t.slug} value={t.slug}>
              {t.name}
            </option>
          ))}
        </select>
      </div>
    </div>
  );

  if (loading) return <>{picker}<Loading label="Picking questions…" /></>;
  if (error || !cards) return <>{picker}<ErrorNote error={error ?? "Couldn't load a quiz."} /></>;
  if (cards.length === 0) {
    return (
      <>
        {picker}
        <p className="text-muted">No quiz questions for this topic yet. Try another topic.</p>
      </>
    );
  }

  const card = cards[index];
  if (!card) {
    return (
      <>
        {picker}
        <div className="panel p-6 text-center">
          <h2 className="font-serif text-2xl font-semibold">
            You got {score} of {cards.length}
          </h2>
          <p className="mt-2 text-muted">Your answers have been added to your review schedule.</p>
          <div className="mt-5 flex flex-wrap justify-center gap-3">
            <button type="button" className="btn btn-primary" onClick={() => restart()}>
              Another round
            </button>
            <Link href="/review" className="btn">
              Go to review
            </Link>
          </div>
        </div>
      </>
    );
  }

  async function onAnswered(correct: boolean) {
    setAnswered(card.id);
    if (correct) setScore((s) => s + 1);
    setSaveError(null);
    try {
      await api.grade(card.id, correct ? "good" : "again");
    } catch {
      setSaveError("Your answer couldn't be saved to your review, but you can keep going.");
    }
  }

  return (
    <>
      {picker}
      <p className="text-sm text-muted" aria-live="polite">
        Question {index + 1} of {cards.length} · Score {score}
      </p>
      <Quiz key={`${round}-${card.id}`} quiz={card.quiz!} onAnswered={onAnswered} />
      {answered === card.id ? (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-muted">
            From{" "}
            <Link href={`/ideas/${card.id}`} className="link">
              {card.title}
            </Link>{" "}
            · {card.credit}
          </p>
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => {
              setIndex((i) => i + 1);
              setAnswered(null);
            }}
          >
            {index + 1 < cards.length ? "Next question" : "See results"}
          </button>
        </div>
      ) : null}
      <ErrorNote error={saveError} />
    </>
  );
}
