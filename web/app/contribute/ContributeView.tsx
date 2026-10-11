"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { ContributionStatus } from "@/components/ContributionStatus";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { WordCounter } from "@/components/WordCounter";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { SOURCE_KINDS, TOPICS, topicName } from "@/lib/content";
import { useLoad } from "@/lib/use-load";
import { BODY_MAX_WORDS, BODY_MIN_WORDS, countWords } from "@/lib/words";
import type { Contribution, NewContribution } from "@/lib/types";

export function ContributeView() {
  const [version, setVersion] = useState(0);
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Contribute an idea</h1>
      <p className="mt-2 text-muted">
        Share one idea from a book, article or talk in your own words. A moderator checks every contribution before
        it&apos;s published, with a credit and link back to the source.
      </p>
      <div className="mt-8">
        <RequireAuth message="Sign in to contribute ideas to the library.">
          <ContributeForm onSubmitted={() => setVersion((v) => v + 1)} />
          <MyContributions version={version} />
        </RequireAuth>
      </div>
    </div>
  );
}

const EMPTY_QUIZ = { question: "", options: ["", "", ""], answer: 0, explanation: "" };

function ContributeForm({ onSubmitted }: { onSubmitted: () => void }) {
  const { api } = useAuth();
  const [src, setSrc] = useState({ title: "", authors: "", url: "", kind: "book" });
  const [topic, setTopic] = useState("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [applyIt, setApplyIt] = useState("");
  const [withQuiz, setWithQuiz] = useState(false);
  const [quiz, setQuiz] = useState(EMPTY_QUIZ);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<Contribution | null>(null);

  const words = countWords(body);
  const bodyOk = words >= BODY_MIN_WORDS && words <= BODY_MAX_WORDS;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!bodyOk) {
      setError(`The idea needs ${BODY_MIN_WORDS}–${BODY_MAX_WORDS} words; it has ${words}.`);
      return;
    }
    const options = quiz.options.map((o) => o.trim()).filter(Boolean);
    if (withQuiz && (options.length < 2 || !quiz.question.trim() || !quiz.options[quiz.answer]?.trim())) {
      setError("A quiz needs a question, at least two options and a marked correct answer.");
      return;
    }
    const payload: NewContribution = {
      source: {
        title: src.title.trim(),
        authors: src.authors.split(",").map((a) => a.trim()).filter(Boolean),
        url: src.url.trim(),
        kind: src.kind,
      },
      topic,
      title: title.trim(),
      body: body.trim(),
      apply_it: applyIt.trim(),
    };
    if (withQuiz) {
      const answerText = quiz.options[quiz.answer].trim();
      payload.quiz = {
        question: quiz.question.trim(),
        options,
        answer: options.indexOf(answerText),
        ...(quiz.explanation.trim() ? { explanation: quiz.explanation.trim() } : {}),
      };
    }
    setBusy(true);
    try {
      const c = await api.contribute(payload);
      setSent(c);
      setTitle("");
      setBody("");
      setApplyIt("");
      setQuiz(EMPTY_QUIZ);
      setWithQuiz(false);
      onSubmitted();
    } catch (err) {
      setError(isApiError(err) ? err.message : "Couldn't send your contribution.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="space-y-8">
      <fieldset className="panel space-y-4 p-5">
        <legend className="px-1 font-serif text-xl font-semibold">The source</legend>
        <div>
          <label htmlFor="src-title" className="label">Title</label>
          <input id="src-title" className="field" required maxLength={200} value={src.title}
            onChange={(e) => setSrc({ ...src, title: e.target.value })} placeholder="e.g. Deep Work" />
        </div>
        <div>
          <label htmlFor="src-authors" className="label">Authors</label>
          <input id="src-authors" className="field" required value={src.authors} aria-describedby="src-authors-hint"
            onChange={(e) => setSrc({ ...src, authors: e.target.value })} placeholder="e.g. Cal Newport" />
          <p id="src-authors-hint" className="hint">Separate several authors with commas.</p>
        </div>
        <div className="grid gap-4 sm:grid-cols-[1fr_12rem]">
          <div>
            <label htmlFor="src-url" className="label">Link to the source</label>
            <input id="src-url" type="url" className="field" required value={src.url}
              onChange={(e) => setSrc({ ...src, url: e.target.value })} placeholder="https://" />
          </div>
          <div>
            <label htmlFor="src-kind" className="label">Kind</label>
            <select id="src-kind" className="field capitalize" value={src.kind}
              onChange={(e) => setSrc({ ...src, kind: e.target.value })}>
              {SOURCE_KINDS.map((k) => <option key={k} value={k}>{k}</option>)}
            </select>
          </div>
        </div>
      </fieldset>

      <fieldset className="panel space-y-4 p-5">
        <legend className="px-1 font-serif text-xl font-semibold">The idea</legend>
        <div>
          <label htmlFor="topic" className="label">Topic</label>
          <select id="topic" className="field" required value={topic} onChange={(e) => setTopic(e.target.value)}>
            <option value="" disabled>Choose a topic</option>
            {TOPICS.map((t) => <option key={t.slug} value={t.slug}>{t.name}</option>)}
          </select>
        </div>
        <div>
          <label htmlFor="title" className="label">The idea in one line</label>
          <input id="title" className="field" required maxLength={90} value={title} aria-describedby="title-hint"
            onChange={(e) => setTitle(e.target.value)} />
          <p id="title-hint" className="hint">{title.length}/90 characters</p>
        </div>
        <div>
          <label htmlFor="body" className="label">Explain it in your own words</label>
          <textarea id="body" className="field min-h-48 resize-y text-lg leading-relaxed" required maxLength={1200}
            value={body} onChange={(e) => setBody(e.target.value)} aria-describedby="body-count body-hint" />
          <WordCounter text={body} id="body-count" />
          <p id="body-hint" className="hint">Plain text. Leave a blank line between paragraphs. No long quotes.</p>
        </div>
        <div>
          <label htmlFor="apply" className="label">Apply it</label>
          <textarea id="apply" className="field min-h-20 resize-y" required maxLength={240} value={applyIt}
            onChange={(e) => setApplyIt(e.target.value)} aria-describedby="apply-hint" />
          <p id="apply-hint" className="hint">One small action or reflection question. {applyIt.length}/240</p>
        </div>
      </fieldset>

      <fieldset className="panel space-y-4 p-5">
        <legend className="px-1 font-serif text-xl font-semibold">Quiz (optional)</legend>
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={withQuiz} onChange={(e) => setWithQuiz(e.target.checked)} className="size-4" />
          Add a question to help readers remember this idea
        </label>
        {withQuiz ? (
          <>
            <div>
              <label htmlFor="quiz-q" className="label">Question</label>
              <input id="quiz-q" className="field" maxLength={200} value={quiz.question}
                onChange={(e) => setQuiz({ ...quiz, question: e.target.value })} />
            </div>
            <div role="radiogroup" aria-labelledby="quiz-options-label" className="space-y-2">
              <p id="quiz-options-label" className="label">Options (mark the correct one)</p>
              {quiz.options.map((opt, i) => (
                <div key={i} className="flex items-center gap-2">
                  <input type="radio" name="quiz-answer" aria-label={`Option ${i + 1} is correct`}
                    checked={quiz.answer === i} onChange={() => setQuiz({ ...quiz, answer: i })} className="size-4 shrink-0" />
                  <label htmlFor={`quiz-opt-${i}`} className="sr-only">Option {i + 1}</label>
                  <input id={`quiz-opt-${i}`} className="field" maxLength={120} value={opt}
                    onChange={(e) => setQuiz({ ...quiz, options: quiz.options.map((o, j) => (j === i ? e.target.value : o)) })} />
                  {quiz.options.length > 2 ? (
                    <button type="button" className="btn btn-small btn-ghost shrink-0" aria-label={`Remove option ${i + 1}`}
                      onClick={() => setQuiz({ ...quiz, options: quiz.options.filter((_, j) => j !== i), answer: quiz.answer >= i && quiz.answer > 0 ? quiz.answer - 1 : quiz.answer })}>
                      ✕
                    </button>
                  ) : null}
                </div>
              ))}
              {quiz.options.length < 4 ? (
                <button type="button" className="btn btn-small" onClick={() => setQuiz({ ...quiz, options: [...quiz.options, ""] })}>
                  Add option
                </button>
              ) : null}
            </div>
            <div>
              <label htmlFor="quiz-exp" className="label">Explanation <span className="font-normal text-muted">(optional)</span></label>
              <input id="quiz-exp" className="field" maxLength={300} value={quiz.explanation}
                onChange={(e) => setQuiz({ ...quiz, explanation: e.target.value })} />
            </div>
          </>
        ) : null}
      </fieldset>

      <ErrorNote error={error} />
      {sent ? (
        <p role="status" className="rounded-lg border border-ok px-3 py-2 text-ok">
          Thanks! “{sent.title}” is waiting for a moderator.
        </p>
      ) : null}
      <button type="submit" className="btn btn-primary" disabled={busy}>
        {busy ? "Sending…" : "Send for review"}
      </button>
    </form>
  );
}

function MyContributions({ version }: { version: number }) {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.myContributions().then((r) => r.contributions), [api, token, version]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad(loader);

  return (
    <section aria-labelledby="mine-title" className="mt-12">
      <h2 id="mine-title" className="font-serif text-2xl font-semibold">My contributions</h2>
      {loading ? (
        <Loading />
      ) : error ? (
        <ErrorNote error={error} />
      ) : !data?.length ? (
        <p className="mt-3 text-muted">You haven&apos;t contributed any ideas yet.</p>
      ) : (
        <ul className="mt-4 grid gap-3">
          {data.map((c) => (
            <li key={c.id} className="panel p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="font-serif text-lg font-semibold">{c.title}</h3>
                <ContributionStatus status={c.status} />
              </div>
              <p className="mt-1 text-sm text-muted">
                {c.source.title} · {topicName(c.topic)} · {new Date(c.created_at).toLocaleDateString()}
              </p>
              {c.moderator_note ? <p className="mt-2 text-sm"><strong>Moderator:</strong> {c.moderator_note}</p> : null}
              {c.card_id ? (
                <p className="mt-2 text-sm">
                  <Link href={`/ideas/${c.card_id}`} className="link">See the published card</Link>
                </p>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
