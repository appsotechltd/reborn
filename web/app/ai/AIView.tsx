"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { AIChart } from "@/components/AIChart";
import { CitedText } from "@/components/CitedText";
import { ErrorNote, Loading, RequireAuth } from "@/components/SignInPrompt";
import { allowanceShare, packPrice, packRate, rateLabel, rateText, recordingFormat, resetLabel, units, walletSummary } from "@/lib/ai";
import { isApiError } from "@/lib/api";
import { useAuth, useHydrated } from "@/lib/auth";
import type { AIConversation, AIMessage, AIStatus, AIWallet } from "@/lib/types";
import { useLoad } from "@/lib/use-load";

const SUGGESTIONS = [
  "Help me build a morning routine from ideas in the library",
  "Draw a chart of a 7-day plan to go to bed 30 minutes earlier",
  "Sketch a simple picture to remind me to breathe slowly",
];

export function AIView({ topup = null }: { topup?: string | null }) {
  return (
    <div className="mx-auto max-w-read">
      <p className="eyebrow">Premium</p>
      <h1 className="mt-1 font-serif text-4xl font-semibold tracking-tight">Reborn AI</h1>
      <p className="mt-2 text-muted">
        Talk or type to think ideas through. Reborn AI draws on the library and links every card it uses, can save cards to
        your collections, and can make charts, sketches and pictures. It isn&apos;t medical, legal or financial advice.
      </p>
      <div className="mt-8">
        <RequireAuth message="Sign in to use Reborn AI.">
          <AIApp topup={topup} />
        </RequireAuth>
      </div>
    </div>
  );
}

function AIApp({ topup }: { topup: string | null }) {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.aiStatus(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data, error, loading } = useLoad(loader);
  // The latest wallet from a reply or top-up; until then, the one loaded with the status.
  const [wallet, setWallet] = useState<AIWallet | null>(null);

  if (loading) return <Loading />;
  if (error || !data) return <ErrorNote error={error ?? "Couldn't load Reborn AI."} />;
  if (!data.available) {
    return (
      <div className="panel p-5" role="status">
        <p className="font-semibold">Reborn AI is resting</p>
        <p className="mt-1 text-sm text-muted">It isn&apos;t switched on right now. Please try again later.</p>
      </div>
    );
  }
  if (!data.premium) return <Upsell status={data} />;
  return (
    <>
      {topup ? <TopUpReturn id={topup} onPaid={() => api.aiStatus().then((s) => s.wallet && setWallet(s.wallet)).catch(() => {})} /> : null}
      <Chat status={data} wallet={wallet ?? data.wallet!} setWallet={setWallet} />
    </>
  );
}

function Upsell({ status }: { status: AIStatus }) {
  return (
    <div className="panel p-5">
      <p className="font-serif text-xl font-semibold">Reborn AI comes with Premium</p>
      <p className="mt-1 text-muted">
        Premium includes {units(250)} of Reborn AI every month, and you can top up any time. Different things use units at
        different rates:
      </p>
      <RateList status={status} />
      <Link href="/premium" className="btn btn-primary mt-4">
        See Premium
      </Link>
    </div>
  );
}

function RateList({ status }: { status: AIStatus }) {
  return (
    <ul className="mt-3 grid gap-1 text-sm" aria-label="AI unit rates">
      {status.rates.map((r) => (
        <li key={r.kind} className="flex justify-between gap-4 border-b border-line py-1 last:border-0">
          <span>{rateLabel(r)}</span>
          <span className="font-semibold">{rateText(r)}</span>
        </li>
      ))}
    </ul>
  );
}

function WalletBar({ wallet, onTopUp }: { wallet: AIWallet; onTopUp: () => void }) {
  const share = allowanceShare(wallet);
  return (
    <div className="panel flex flex-wrap items-center gap-x-4 gap-y-2 p-4" data-testid="ai-wallet">
      <div className="min-w-0 flex-1">
        <p className="font-semibold">
          {units(wallet.remaining)} <span className="font-normal text-muted">left</span>
        </p>
        <div
          className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-surface-2"
          role="meter"
          aria-label="Monthly AI units left"
          aria-valuemin={0}
          aria-valuemax={wallet.monthly_units}
          aria-valuenow={wallet.allowance_left}
        >
          <div className="h-full rounded-full bg-accent" style={{ width: `${share * 100}%` }} />
        </div>
        <p className="mt-1 text-xs text-muted">
          {walletSummary(wallet)}. {resetLabel(wallet)}.
        </p>
      </div>
      <button type="button" className="btn btn-small" onClick={onTopUp}>
        Top up
      </button>
    </div>
  );
}

function TopUps({ status, onClose }: { status: AIStatus; onClose: () => void }) {
  const { api } = useAuth();
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  async function buy(pack: string) {
    setBusy(pack);
    setErr(null);
    try {
      const { url } = await api.topUpCheckout(pack);
      window.location.assign(url);
    } catch (e) {
      setErr(
        isApiError(e) && e.code === "topups_unavailable"
          ? "Top-ups on the web are coming soon. You can top up in the Reborn app."
          : isApiError(e)
            ? e.message
            : "Couldn't start the payment. Please try again.",
      );
      setBusy(null);
    }
  }

  return (
    <section className="panel mt-3 p-5" aria-labelledby="topup-title">
      <div className="flex items-start justify-between gap-4">
        <h2 id="topup-title" className="font-serif text-xl font-semibold">
          Top up AI units
        </h2>
        <button type="button" className="btn btn-small" onClick={onClose}>
          Close
        </button>
      </div>
      <p className="mt-1 text-sm text-muted">
        Top-up units never expire. They&apos;re used after your monthly units run out.
      </p>
      <ul className="mt-4 grid gap-3 sm:grid-cols-3">
        {status.packs.map((p) => (
          <li key={p.id} className="flex flex-col rounded-xl border border-line p-4 text-center">
            <p className="font-semibold">{units(p.units)}</p>
            <p className="mt-1 text-2xl font-semibold">{packPrice(p)}</p>
            <p className="text-xs text-muted">{packRate(p)}</p>
            <button
              type="button"
              className="btn btn-primary btn-small mt-3"
              disabled={!status.providers.stripe || busy !== null}
              onClick={() => buy(p.id)}
            >
              {busy === p.id ? "Opening…" : "Buy"}
            </button>
          </li>
        ))}
      </ul>
      {!status.providers.stripe ? (
        <p role="status" className="mt-3 text-sm text-muted">
          Top-ups on the web are coming soon. You can top up in the Reborn app.
        </p>
      ) : null}
      <ErrorNote error={err} />
      <details className="mt-4 text-sm">
        <summary className="cursor-pointer font-semibold">What uses units</summary>
        <RateList status={status} />
      </details>
    </section>
  );
}

/** After Stripe Checkout, waits for the payment to be confirmed. */
function TopUpReturn({ id, onPaid }: { id: string; onPaid: () => void }) {
  const { api } = useAuth();
  const [state, setState] = useState<"waiting" | "paid" | "slow">("waiting");
  useEffect(() => {
    let cancelled = false;
    let tries = 0;
    const check = async () => {
      try {
        const t = await api.topUp(id);
        if (cancelled) return;
        if (t.status === "paid") {
          setState("paid");
          onPaid();
          return;
        }
      } catch {
        // keep trying
      }
      if (++tries >= 10) setState("slow");
      else setTimeout(check, 2000);
    };
    check();
    return () => {
      cancelled = true;
    };
  }, [api, id]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div role="status" className="mb-4 rounded-xl border border-ok bg-apply px-5 py-3 text-sm text-apply-fg">
      {state === "paid"
        ? "Thank you! Your AI units have been added."
        : state === "slow"
          ? "Thanks! Your payment is still being confirmed. Your units will appear shortly."
          : "Thanks! Confirming your payment…"}
    </div>
  );
}

type Problem = { kind: "out_of_units" } | { kind: "rate_limited" } | { kind: "error"; message: string };

function Chat({ status, wallet, setWallet }: { status: AIStatus; wallet: AIWallet; setWallet: (w: AIWallet) => void }) {
  const { api } = useAuth();
  const [convs, setConvs] = useState<AIConversation[]>([]);
  const [convId, setConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<AIMessage[]>([]);
  const [pending, setPending] = useState<string | null>(null);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [showTopUp, setShowTopUp] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    api
      .aiConversations()
      .then((r) => setConvs(r.conversations))
      .catch(() => {});
  }, [api]);

  useEffect(() => {
    endRef.current?.scrollIntoView?.({ block: "end", behavior: "smooth" });
  }, [messages.length, busy]);

  async function open(id: string) {
    setProblem(null);
    if (!id) {
      setConvId(null);
      setMessages([]);
      return;
    }
    try {
      const r = await api.aiConversation(id);
      setConvId(id);
      setMessages(r.messages);
    } catch (e) {
      setProblem({ kind: "error", message: isApiError(e) ? e.message : "Couldn't open that chat." });
    }
  }

  async function remove() {
    if (!convId || !window.confirm("Delete this chat?")) return;
    try {
      await api.deleteAIConversation(convId);
      setConvs((cs) => cs.filter((c) => c.id !== convId));
      setConvId(null);
      setMessages([]);
    } catch (e) {
      setProblem({ kind: "error", message: isApiError(e) ? e.message : "Couldn't delete that chat." });
    }
  }

  function fail(e: unknown) {
    if (isApiError(e) && e.code === "out_of_units") {
      setProblem({ kind: "out_of_units" });
      setShowTopUp(true);
      api.aiStatus().then((s) => s.wallet && setWallet(s.wallet)).catch(() => {});
    } else if (isApiError(e) && e.status === 429) setProblem({ kind: "rate_limited" });
    else setProblem({ kind: "error", message: isApiError(e) ? e.message : "Something went wrong." });
  }

  async function run(label: string, call: () => ReturnType<typeof api.aiChat>, restore?: string) {
    setPending(label);
    setBusy(true);
    setProblem(null);
    try {
      const r = await call();
      setMessages((m) => [...m, r.user_message, r.message]);
      setWallet(r.wallet);
      if (r.conversation.id !== convId) {
        setConvId(r.conversation.id);
        setConvs((cs) => [r.conversation, ...cs.filter((c) => c.id !== r.conversation.id)]);
      }
    } catch (e) {
      if (restore !== undefined) setInput(restore);
      fail(e);
    } finally {
      setPending(null);
      setBusy(false);
    }
  }

  function send(text: string) {
    const message = text.trim();
    if (!message || busy) return;
    setInput("");
    run(message, () => api.aiChat(message, convId), message);
  }

  function sendVoice(audio: Blob, filename: string) {
    run("🎙 Voice message", () => api.aiVoice(audio, filename, convId));
  }

  return (
    <div>
      <WalletBar wallet={wallet} onTopUp={() => setShowTopUp((v) => !v)} />
      {showTopUp ? <TopUps status={status} onClose={() => setShowTopUp(false)} /> : null}

      <div className="mt-4 flex items-end gap-2">
        <div className="min-w-0 flex-1">
          <label htmlFor="ai-chats" className="label">
            Your chats
          </label>
          <select id="ai-chats" className="field w-full" value={convId ?? ""} onChange={(e) => open(e.target.value)} disabled={busy}>
            <option value="">New chat</option>
            {convs.map((c) => (
              <option key={c.id} value={c.id}>
                {c.title}
              </option>
            ))}
          </select>
        </div>
        {convId ? (
          <button type="button" className="btn btn-small" onClick={remove} disabled={busy}>
            Delete
          </button>
        ) : null}
      </div>

      {messages.length === 0 && !pending ? (
        <div className="panel mt-6 p-5">
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

      <ol className="mt-6 space-y-6" aria-label="Conversation" aria-live="polite">
        {messages.map((m) =>
          m.role === "user" ? (
            <li key={m.id} className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-sm bg-accent-soft px-4 py-3">
                <span className="sr-only">You: </span>
                {m.voice ? (
                  <span aria-hidden className="mr-1">
                    🎙
                  </span>
                ) : null}
                {m.content}
              </div>
            </li>
          ) : (
            <Reply key={m.id} message={m} onWallet={setWallet} onFail={fail} />
          ),
        )}
        {pending ? (
          <>
            <li className="flex justify-end">
              <div className="max-w-[85%] rounded-2xl rounded-br-sm bg-accent-soft px-4 py-3 opacity-70">{pending}</div>
            </li>
            <li role="status" className="text-muted">
              Reborn AI is thinking…
            </li>
          </>
        ) : null}
      </ol>

      {problem ? <ProblemNote problem={problem} onTopUp={() => setShowTopUp(true)} /> : null}
      <div ref={endRef} />

      <form
        className="mt-6"
        onSubmit={(e) => {
          e.preventDefault();
          send(input);
        }}
      >
        <label htmlFor="ai-input" className="label">
          Message Reborn AI
        </label>
        <textarea
          id="ai-input"
          className="field min-h-24 w-full resize-y"
          value={input}
          maxLength={8000}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send(input);
            }
          }}
          placeholder="Ask anything about an idea, a habit, a plan…"
        />
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <button type="submit" className="btn btn-primary" disabled={busy || !input.trim()}>
            Send
          </button>
          <VoiceButton disabled={busy} onRecorded={sendVoice} />
          <span className="ml-auto text-xs text-muted">1 unit per reply</span>
        </div>
      </form>
    </div>
  );
}

function Reply({ message: m, onWallet, onFail }: { message: AIMessage; onWallet: (w: AIWallet) => void; onFail: (e: unknown) => void }) {
  const { api } = useAuth();
  const [loadingAudio, setLoadingAudio] = useState(false);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [cost, setCost] = useState(m.units);

  async function listen() {
    setLoadingAudio(true);
    try {
      const r = await api.aiSpeech(m.id);
      onWallet(r.wallet);
      setCost((c) => c + r.units);
      setAudioUrl(r.url);
    } catch (e) {
      onFail(e);
    } finally {
      setLoadingAudio(false);
    }
  }

  return (
    <li>
      <div className="text-lg leading-relaxed">
        <span className="sr-only">Reborn AI: </span>
        <CitedText text={m.content} citations={m.citations} />
      </div>
      {m.attachments.length ? (
        <div className="mt-3 grid gap-3">
          {m.attachments.map((a, i) =>
            a.type === "chart" ? (
              <AIChart key={i} chart={a.chart} />
            ) : (
              <figure key={i}>
                {/* eslint-disable-next-line @next/next/no-img-element -- media is served from R2 */}
                <img src={a.url} alt={a.alt} width={a.width} height={a.height} className="h-auto w-full rounded-xl border border-line" loading="lazy" />
                <figcaption className="mt-1 text-xs text-muted capitalize">{a.style}</figcaption>
              </figure>
            ),
          )}
        </div>
      ) : null}
      {m.citations.length ? (
        <div className="mt-3">
          <p className="eyebrow">Ideas cited</p>
          <ol className="mt-2 grid gap-2">
            {m.citations.map((c, ci) => (
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
      <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-muted">
        {audioUrl ? (
          <audio controls autoPlay src={audioUrl} className="h-8 max-w-full" aria-label="Reply read aloud" />
        ) : (
          <button type="button" className="btn btn-small" onClick={listen} disabled={loadingAudio}>
            {loadingAudio ? "Preparing…" : "Listen"}
          </button>
        )}
        <span>Used {units(cost)}</span>
      </div>
    </li>
  );
}

/** Records a voice message with the microphone, where the browser allows it. */
function VoiceButton({ disabled, onRecorded }: { disabled: boolean; onRecorded: (audio: Blob, filename: string) => void }) {
  const [recording, setRecording] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const rec = useRef<MediaRecorder | null>(null);

  const hydrated = useHydrated();
  const supported = hydrated && typeof window.MediaRecorder !== "undefined" && !!navigator.mediaDevices;
  if (!supported) return null;

  async function start() {
    setErr(null);
    const format = recordingFormat((t) => MediaRecorder.isTypeSupported(t));
    if (!format) return setErr("This browser can't record audio.");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const r = new MediaRecorder(stream, { mimeType: format.mimeType });
      const chunks: Blob[] = [];
      r.ondataavailable = (e) => e.data.size && chunks.push(e.data);
      r.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        setRecording(false);
        const blob = new Blob(chunks, { type: format.mimeType });
        if (blob.size > 0) onRecorded(blob, `voice.${format.ext}`);
      };
      rec.current = r;
      r.start();
      setRecording(true);
    } catch {
      setErr("Allow the microphone to send a voice message.");
    }
  }

  return (
    <>
      <button
        type="button"
        className={recording ? "btn btn-primary" : "btn"}
        disabled={disabled && !recording}
        aria-pressed={recording}
        onClick={() => (recording ? rec.current?.stop() : start())}
      >
        {recording ? "■ Stop and send" : "🎙 Speak"}
      </button>
      {err ? (
        <span role="alert" className="text-sm text-bad">
          {err}
        </span>
      ) : null}
    </>
  );
}

function ProblemNote({ problem, onTopUp }: { problem: Problem; onTopUp: () => void }) {
  if (problem.kind === "out_of_units") {
    return (
      <div role="alert" className="mt-6 rounded-xl border border-warn-border bg-warn px-5 py-4 text-warn-fg">
        <p className="font-semibold">You&apos;re out of AI units</p>
        <p className="mt-1 text-sm">
          Top up to keep going, or wait for your monthly units to come back.{" "}
          <button type="button" className="link" onClick={onTopUp}>
            See top-ups
          </button>
        </p>
      </div>
    );
  }
  if (problem.kind === "rate_limited") {
    return (
      <div role="alert" className="mt-6 rounded-xl border border-line bg-surface-2 px-5 py-4">
        <p className="font-semibold">Time for a pause</p>
        <p className="mt-1 text-sm text-muted">You&apos;ve sent a lot of messages this hour. Try again in a little while.</p>
      </div>
    );
  }
  return <ErrorNote error={problem.message} />;
}
