"use client";

import Link from "next/link";
import { useCallback, useState, type ReactNode } from "react";
import { ErrorNote, Loading } from "@/components/SignInPrompt";
import { units, walletSummary } from "@/lib/ai";
import { isApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { audioUnits, IMAGE_STYLES, imageUnits, monthlyBuys, videoUnits } from "@/lib/studio";
import { useLoad } from "@/lib/use-load";
import type { AIWallet, Card, ImageShape, ImageStyle, StudioInfo, StudioMedia, StudioResult } from "@/lib/types";

const WORKING: Record<StudioMedia, string> = {
  image: "Making your picture…",
  audio: "Making your audio…",
  video: "Making your video… this can take a minute",
};

/** What went wrong with a studio request, in plain words, with where to go next when there is somewhere. */
function studioError(err: unknown): { text: string; link?: { href: string; label: string } } {
  if (!isApiError(err)) return { text: "Something went wrong. Please try again." };
  switch (err.code) {
    case "out_of_units":
      return { text: "Not enough AI units.", link: { href: "/ai", label: "Top up" } };
    case "premium_required":
      return { text: "The card studio comes with Premium.", link: { href: "/premium", label: "See Premium" } };
    case "ai_unavailable":
      return { text: "AI isn't switched on yet." };
    case "declined":
      return { text: err.message || "That can't be made. Try describing it differently." };
  }
  return { text: err.message };
}

/**
 * The card studio on one of my cards: a picture, audio or an illustrated video made with Reborn AI,
 * each priced in AI units on its button before spending. Premium only. Each job runs on the server
 * for up to a couple of minutes and is saved even if the page is closed.
 */
export function CardStudio({ card, onCard }: { card: Card; onCard: (card: Card) => void }) {
  const { api, token } = useAuth();
  const loader = useCallback(() => api.studio(), [api, token]); // eslint-disable-line react-hooks/exhaustive-deps
  const { data: studio, error, loading } = useLoad<StudioInfo>(loader);
  const [wallet, setWallet] = useState<AIWallet | null>(null);

  return (
    <section aria-labelledby="studio-title" className="mt-12">
      <p className="eyebrow">Premium</p>
      <h2 id="studio-title" className="mt-1 font-serif text-2xl font-semibold">
        Card studio
      </h2>
      <p className="mt-1 text-sm text-muted">Add a picture, audio or a video made with Reborn AI. It uses AI units.</p>
      <div className="mt-4">
        {loading ? (
          <Loading />
        ) : error || !studio ? (
          <ErrorNote error={error ?? "Couldn't load the card studio."} />
        ) : !studio.available ? (
          <p role="status" className="panel p-5">
            AI isn&apos;t switched on yet.
          </p>
        ) : !studio.premium ? (
          <div className="panel p-5">
            <p className="font-semibold">The card studio comes with Premium</p>
            <p className="mt-1 text-sm text-muted">
              Premium includes {units(studio.monthly_units)} a month: {monthlyBuys(studio.monthly_units, studio.rates)}.
            </p>
            <Link href="/premium" className="btn btn-primary mt-4">
              See Premium
            </Link>
          </div>
        ) : (
          <Studio card={card} studio={studio} wallet={wallet ?? studio.wallet} onCard={onCard} onWallet={setWallet} />
        )}
      </div>
    </section>
  );
}

function Studio({
  card,
  studio,
  wallet,
  onCard,
  onWallet,
}: {
  card: Card;
  studio: StudioInfo;
  wallet: AIWallet | null;
  onCard: (card: Card) => void;
  onWallet: (w: AIWallet) => void;
}) {
  const { api } = useAuth();
  const [style, setStyle] = useState<ImageStyle>("illustration");
  const [prompt, setPrompt] = useState("");
  const [shape, setShape] = useState<ImageShape>("landscape");
  const [voice, setVoice] = useState(card.audio?.voice || card.video?.voice || studio.voices[0]?.id || "af_heart");
  const [working, setWorking] = useState<StudioMedia | null>(null);
  const [removing, setRemoving] = useState<StudioMedia | null>(null);
  const [problem, setProblem] = useState<ReturnType<typeof studioError> | null>(null);
  const [made, setMade] = useState<string | null>(null);

  const prices = {
    image: imageUnits(style, studio.rates),
    audio: audioUnits(card),
    video: videoUnits(card, studio.video_scenes, studio.rates),
  };
  const busy = working !== null || removing !== null;

  async function make(kind: StudioMedia, run: () => Promise<StudioResult>) {
    setWorking(kind);
    setProblem(null);
    setMade(null);
    try {
      const res = await run();
      onCard(res.card);
      onWallet(res.wallet);
      setMade(`Done. That used ${units(res.units)}.`);
    } catch (err) {
      setProblem(studioError(err));
    } finally {
      setWorking(null);
    }
  }

  async function remove(kind: StudioMedia) {
    setRemoving(kind);
    setProblem(null);
    setMade(null);
    try {
      onCard(await api.deleteCardMedia(card.id, kind));
    } catch (err) {
      setProblem(studioError(err));
    } finally {
      setRemoving(null);
    }
  }

  const voicePicker = (id: string) => (
    <div>
      <label htmlFor={id} className="label">
        Voice
      </label>
      <select id={id} className="field" value={voice} onChange={(e) => setVoice(e.target.value)} disabled={busy}>
        {studio.voices.map((v) => (
          <option key={v.id} value={v.id}>
            {v.name}
          </option>
        ))}
      </select>
    </div>
  );

  return (
    <div className="grid gap-4">
      {wallet ? (
        <div className="panel p-4" data-testid="studio-wallet">
          <p className="font-semibold">
            {units(wallet.remaining)} <span className="font-normal text-muted">left</span>
          </p>
          <p className="mt-1 text-sm text-muted">{walletSummary(wallet)}.</p>
          <p className="mt-1 text-xs text-muted">
            {units(studio.monthly_units)} a month buy {monthlyBuys(studio.monthly_units, studio.rates)}.{" "}
            <Link href="/ai" className="link">
              Top up
            </Link>
          </p>
        </div>
      ) : null}

      {working ? (
        <p role="status" className="panel flex items-center gap-3 p-4 font-semibold" data-testid="studio-working">
          <span aria-hidden="true" className="size-4 shrink-0 animate-spin rounded-full border-2 border-accent border-t-transparent" />
          {WORKING[working]}
        </p>
      ) : null}
      {made ? (
        <p role="status" className="text-sm font-semibold text-ok">
          {made}
        </p>
      ) : null}
      {problem ? (
        <p role="alert" className="rounded-lg border border-bad px-3 py-2 text-sm text-bad">
          {problem.text}{" "}
          {problem.link ? (
            <Link href={problem.link.href} className="link font-semibold">
              {problem.link.label}
            </Link>
          ) : null}
        </p>
      ) : null}

      <Tool title="Picture" has={!!card.image} removing={removing === "image"} onRemove={() => remove("image")} disabled={busy}>
        <fieldset>
          <legend className="label">Style</legend>
          <div className="flex flex-wrap gap-2">
            {IMAGE_STYLES.map((s) => (
              <button
                key={s.id}
                type="button"
                aria-pressed={style === s.id}
                disabled={busy}
                className={`chip min-h-9 pointer-coarse:min-h-11 ${style === s.id ? "chip-on" : "hover:text-fg"}`}
                onClick={() => setStyle(s.id)}
              >
                {s.label} · {imageUnits(s.id, studio.rates)}
              </button>
            ))}
          </div>
        </fieldset>
        <div>
          <label htmlFor="studio-prompt" className="label">
            Describe the image <span className="font-normal text-muted">(optional)</span>
          </label>
          <textarea
            id="studio-prompt"
            className="field min-h-20 resize-y"
            maxLength={1000}
            placeholder="Leave empty to picture the card"
            value={prompt}
            disabled={busy}
            onChange={(e) => setPrompt(e.target.value)}
          />
        </div>
        <div>
          <label htmlFor="studio-shape" className="label">
            Shape
          </label>
          <select id="studio-shape" className="field" value={shape} disabled={busy} onChange={(e) => setShape(e.target.value as ImageShape)}>
            <option value="landscape">Landscape</option>
            <option value="square">Square</option>
            <option value="portrait">Portrait</option>
          </select>
        </div>
        <MakeButton
          disabled={busy}
          onClick={() =>
            make("image", () => api.makeCardImage(card.id, { style, shape, prompt: prompt.trim() || undefined }))
          }
        >
          {card.image ? "Make a new picture" : "Make picture"} · {units(prices.image)}
        </MakeButton>
      </Tool>

      <Tool title="Audio" has={!!card.audio} removing={removing === "audio"} onRemove={() => remove("audio")} disabled={busy}>
        <p className="text-sm text-muted">The card read aloud: 1 unit per 50 words.</p>
        {voicePicker("studio-audio-voice")}
        <MakeButton disabled={busy} onClick={() => make("audio", () => api.makeCardAudio(card.id, voice))}>
          {card.audio ? "Make new audio" : "Make audio"} · {units(prices.audio)}
        </MakeButton>
      </Tool>

      <Tool title="Video" has={!!card.video} removing={removing === "video"} onRemove={() => remove("video")} disabled={busy}>
        <p className="text-sm text-muted">
          {studio.video_scenes} illustrations that move with the narration.
        </p>
        {voicePicker("studio-video-voice")}
        <MakeButton disabled={busy} onClick={() => make("video", () => api.makeCardVideo(card.id, voice))}>
          {card.video ? "Make a new video" : "Make video"} · {units(prices.video)}
        </MakeButton>
      </Tool>
    </div>
  );
}

function Tool({
  title,
  has,
  removing,
  onRemove,
  disabled,
  children,
}: {
  title: string;
  has: boolean;
  removing: boolean;
  onRemove: () => void;
  disabled: boolean;
  children: ReactNode;
}) {
  return (
    <section className="panel space-y-3 p-5" aria-label={title}>
      <div className="flex items-center justify-between gap-3">
        <h3 className="font-serif text-xl font-semibold">{title}</h3>
        {has ? (
          <button type="button" className="btn btn-small btn-ghost text-bad" onClick={onRemove} disabled={disabled}>
            {removing ? "Removing…" : "Remove"}
            <span className="sr-only"> {title.toLowerCase()}</span>
          </button>
        ) : null}
      </div>
      {children}
    </section>
  );
}

function MakeButton({ disabled, onClick, children }: { disabled: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button type="button" className="btn btn-primary" disabled={disabled} onClick={onClick}>
      {children}
    </button>
  );
}
