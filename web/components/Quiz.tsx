"use client";

import { useId, useState } from "react";
import type { Quiz as QuizType } from "@/lib/types";

interface QuizProps {
  quiz: QuizType;
  title?: string;
  /** Called once when the reader checks an answer. */
  onAnswered?: (correct: boolean) => void;
}

/** "Test yourself": pick an option, check it, see the explanation. */
export function Quiz({ quiz, title = "Test yourself", onAnswered }: QuizProps) {
  const id = useId();
  const [choice, setChoice] = useState<number | null>(null);
  const [checked, setChecked] = useState(false);
  const correct = checked && choice === quiz.answer;

  function check(e: React.FormEvent) {
    e.preventDefault();
    if (choice === null || checked) return;
    setChecked(true);
    onAnswered?.(choice === quiz.answer);
  }

  return (
    <form onSubmit={check} className="panel mt-8 p-5" aria-labelledby={`${id}-title`}>
      <h3 id={`${id}-title`} className="eyebrow">
        {title}
      </h3>
      <fieldset className="mt-2" disabled={checked}>
        <legend className="font-serif text-lg font-semibold leading-snug">{quiz.question}</legend>
        <div className="mt-3 grid gap-2">
          {quiz.options.map((opt, i) => {
            const isAnswer = checked && i === quiz.answer;
            const isWrongPick = checked && i === choice && i !== quiz.answer;
            return (
              <label
                key={i}
                className={`flex min-h-11 cursor-pointer items-start gap-3 rounded-lg border px-3 py-2.5 ${
                  isAnswer
                    ? "border-ok bg-apply"
                    : isWrongPick
                      ? "border-bad"
                      : choice === i
                        ? "border-accent bg-accent-soft"
                        : "border-line hover:bg-surface-2"
                }`}
              >
                <input
                  type="radio"
                  name={`${id}-option`}
                  value={i}
                  checked={choice === i}
                  onChange={() => setChoice(i)}
                  className="mt-1 accent-[var(--accent)]"
                />
                <span>
                  {opt}
                  {isAnswer ? <span className="ml-2 text-sm font-semibold text-ok">Correct answer</span> : null}
                  {isWrongPick ? <span className="ml-2 text-sm font-semibold text-bad">Your answer</span> : null}
                </span>
              </label>
            );
          })}
        </div>
      </fieldset>
      {!checked ? (
        <button type="submit" className="btn btn-primary mt-4" disabled={choice === null}>
          Check answer
        </button>
      ) : (
        <div role="status" className="mt-4">
          <p className={`font-semibold ${correct ? "text-ok" : "text-bad"}`}>
            {correct ? "Right!" : "Not quite."}
          </p>
          {quiz.explanation ? <p className="mt-1 text-muted">{quiz.explanation}</p> : null}
        </div>
      )}
    </form>
  );
}
