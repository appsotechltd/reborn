"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { CitedText } from "@/components/CitedText";
import { RequireAuth } from "@/components/SignInPrompt";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { Card, ChatMessage } from "@/lib/types";

interface Turn extends ChatMessage {
  citations?: Card[];
}

type Problem = { kind: "unavailable" } | { kind: "rate_limited" } | { kind: "error"; message: string };

const SUGGESTIONS = [
  "How can I stay calm around difficult people?",
  "What helps me fall asleep faster?",
  "How should I study so I remember more?",
];

export function AskView() {
  return (
    <div className="mx-auto max-w-read">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Ask the guide</h1>
      <p className="mt-2 text-muted">
        Ask a question and the guide answers using only ideas from the Reborn library, with links to every card it
        draws on. It doesn&apos;t browse the web or give medical, legal or financial advice.
      </p>
      <div className="mt-8">
        <RequireAuth message="Sign in to chat with the guide.">
          <Chat />
        </RequireAuth>
      </div>
    </div>
  );
}

function Chat() {
  const { api } = useAuth();
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView?.({ block: "end", behavior: "smooth" });
  }, [turns.length, busy]);

  async function send(text: string) {
    const content = text.trim();
    if (!content || busy) return;
    const history: Turn[] = [...turns, { role: "user", content }];
    setTurns(history);
    setInput("");
    setBusy(true);
    setProblem(null);
    try {
      const res = await api.chat(history.map(({ role, content }) => ({ role, content })));
      setTurns([...history, { role: "assistant", content: res.reply, citations: res.citations }]);
    } catch (err) {
      // Put the question back so it can be sent again.
      setTurns(turns);
      setInput(content);
      if (isApiError(err) && err.status === 503) setProblem({ kind: "unavailable" });
      else if (isApiError(err) && err.status === 429) setProblem({ kind: "rate_limited" });
      else setProblem({ kind: "error", message: isApiError(err) ? err.message : "Something went wrong." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      {turns.length === 0 && !problem ? (
        <div className="panel p-5">
          <p className="font-semibold">Try asking</p>
          <ul className="mt-3 grid gap-2">
            {SUGGESTIONS.map((s) => (
              <li key={s}>
                <button type="button" className="btn btn-small w-full justify-start text-left" onClick={() => send(s)}>
                  {s}
                </button>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <ol className="space-y-6" aria-label="Conversation" aria-live="polite">
        {turns.map((t, i) =>
          t.role === "user" ? (
            <li key={i} className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-sm bg-accent-soft px-4 py-3">
                <span className="sr-only">You: </span>
                {t.content}
              </div>
            </li>
          ) : (
            <li key={i}>
              <div className="text-lg leading-relaxed">
                <span className="sr-only">Guide: </span>
                <CitedText text={t.content} citations={t.citations ?? []} />
              </div>
              {t.citations?.length ? (
                <div className="mt-3">
                  <p className="eyebrow">Ideas cited</p>
                  <ol className="mt-2 grid gap-2">
                    {t.citations.map((c, ci) => (
                      <li key={c.id} className="panel flex gap-3 p-3 text-sm">
                        <span className="font-semibold text-accent-text">{ci + 1}</span>
                        <span className="min-w-0">
                          <Link href={`/ideas/${c.id}`} className="font-semibold hover:underline">
                            {c.title}
                          </Link>
                          <span className="block text-xs text-muted">{c.credit}</span>
                          {c.disclaimer ? <span className="block text-xs text-warn-fg">{c.disclaimer}</span> : null}
                        </span>
                      </li>
                    ))}
                  </ol>
                </div>
              ) : null}
            </li>
          ),
        )}
        {busy ? (
          <li role="status" className="text-muted">
            The guide is looking through the library…
          </li>
        ) : null}
      </ol>

      {problem ? <ProblemPanel problem={problem} /> : null}

      <div ref={endRef} />

      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(input);
        }}
        className="mt-6"
      >
        <label htmlFor="ask-input" className="label">
          Your question
        </label>
        <textarea
          id="ask-input"
          className="field min-h-24 resize-y"
          value={input}
          maxLength={2000}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              send(input);
            }
          }}
          placeholder="Ask about anything in the library…"
        />
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
          <p className="text-xs text-muted">Answers come only from Reborn idea cards. Enter to send, Shift+Enter for a new line.</p>
          <div className="flex gap-2">
            {turns.length ? (
              <button
                type="button"
                className="btn"
                onClick={() => {
                  setTurns([]);
                  setProblem(null);
                }}
                disabled={busy}
              >
                New chat
              </button>
            ) : null}
            <button type="submit" className="btn btn-primary" disabled={busy || !input.trim()}>
              {busy ? "Thinking…" : "Ask"}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
}

function ProblemPanel({ problem }: { problem: Problem }) {
  if (problem.kind === "unavailable") {
    return (
      <div role="alert" className="panel mt-6 p-6 text-center">
        <p aria-hidden="true" className="text-3xl">
          ☾
        </p>
        <h2 className="mt-2 font-serif text-2xl font-semibold">The guide is resting</h2>
        <p className="mt-2 text-muted">
          The AI guide isn&apos;t switched on for this server right now. Everything it knows comes from the library,
          so you can still find answers there.
        </p>
        <div className="mt-5 flex flex-wrap justify-center gap-3">
          <Link href="/search" className="btn btn-primary">
            Search the library
          </Link>
          <Link href="/" className="btn">
            Browse topics
          </Link>
        </div>
      </div>
    );
  }
  if (problem.kind === "rate_limited") {
    return (
      <div role="alert" className="panel mt-6 p-6 text-center">
        <h2 className="font-serif text-2xl font-semibold">Time for a pause</h2>
        <p className="mt-2 text-muted">
          You&apos;ve asked the guide a lot this hour. Your question is saved below. Try again a little later, or
          read through the ideas you&apos;ve already found.
        </p>
        <div className="mt-5 flex justify-center">
          <Link href="/review" className="btn">
            Review your ideas
          </Link>
        </div>
      </div>
    );
  }
  return (
    <p role="alert" className="mt-6 rounded-lg border border-bad px-3 py-2 text-bad">
      {problem.message} Your question is still in the box below.
    </p>
  );
}
