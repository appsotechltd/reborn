"use client";

import Link from "next/link";
import { useState } from "react";
import { isApiError } from "@/lib/api";
import { useAuth, useHydrated } from "@/lib/auth";
import { useListen } from "@/lib/listen";
import {
  bestProgress,
  coverageLabel,
  localProgress,
  resumeIndex,
  summaryByline,
  summaryHref,
  summaryMeta,
} from "@/lib/summaries";
import type { Card, Summary, SummaryProgress } from "@/lib/types";
import { Icon } from "./Icon";
import { ShareMenu } from "./ShareMenu";

/**
 * The summary's cover: always the dark Candlelight look (like videos), so it stands out in the
 * feed as something bigger than one card. A guide with a cover picture shows it behind the text,
 * darkened so the title stays readable.
 */
export function SummaryCover({
  summary,
  headingLevel = "h2",
  href,
  size = "large",
}: {
  summary: Summary;
  headingLevel?: "h1" | "h2" | "h3";
  /** Links the title. */
  href?: string;
  size?: "large" | "small";
}) {
  const Heading = headingLevel;
  return (
    <div
      className="relative overflow-hidden rounded-inset bg-[#1f1710] px-5 py-6 text-[#f2e8d8] sm:px-7 sm:py-8"
      style={{
        backgroundImage: summary.cover
          ? `linear-gradient(to top, rgba(31,23,16,0.96) 30%, rgba(31,23,16,0.55)), url("${summary.cover.url}")`
          : "radial-gradient(120% 90% at 85% 0%, rgba(233,162,59,0.28), transparent 60%)",
        backgroundSize: "cover",
        backgroundPosition: "center",
      }}
      data-summary-cover
    >
      {summary.cover ? (
        <span role="img" aria-label={summary.cover.caption} className="sr-only" data-summary-cover-image />
      ) : null}
      {summary.cover && size === "large" ? <div aria-hidden="true" className="h-24 sm:h-36" /> : null}
      <p className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs font-semibold uppercase tracking-[0.12em] text-[#e9a23b]">
        <Icon name="libraryBooks" className="size-4" />
        <span>{coverageLabel(summary)}</span>
        <span aria-hidden="true">·</span>
        <span className="min-w-0">{summary.topic_name}</span>
      </p>
      <Heading
        id={`summary-${summary.id}-title`}
        className={`mt-3 font-serif font-semibold leading-tight tracking-tight text-balance ${
          size === "large" ? "text-3xl sm:text-4xl" : "text-2xl"
        }`}
      >
        {href ? (
          <Link href={href} className="hover:underline">
            {summary.title}
          </Link>
        ) : (
          summary.title
        )}
      </Heading>
      <p className="mt-2 text-sm text-[#d9cdba]">{summaryByline(summary)}</p>
      <p className="mt-4 inline-flex items-center gap-1.5 rounded-full border border-[#4a3e32] px-3 py-1 text-xs font-semibold text-[#f2e8d8]">
        {summaryMeta(summary)}
      </p>
    </div>
  );
}

/** "Part 4 of 30" with a bar, or "Finished". */
export function SummaryProgressBar({ progress, parts }: { progress: SummaryProgress; parts: number }) {
  const done = progress.finished ? parts : Math.min(parts, progress.position + 1);
  return (
    <div className="flex items-center gap-3 text-sm text-muted" data-summary-progress>
      <div
        className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2"
        role="progressbar"
        aria-label="Reading progress"
        aria-valuemin={0}
        aria-valuemax={parts}
        aria-valuenow={done}
      >
        <div className="h-full rounded-full bg-accent" style={{ width: `${(done / Math.max(1, parts)) * 100}%` }} />
      </div>
      <span className="shrink-0">{progress.finished ? "Finished" : `Part ${done} of ${parts}`}</span>
    </div>
  );
}

/**
 * Plays a summary start to finish in Listen mode, from `from` (zero-based). Loads the parts when
 * they aren't given (the feed only has the cover). While this summary is the session it pauses and
 * resumes it instead.
 */
export function ListenSummaryButton({
  summaryId,
  parts,
  from = 0,
  small = true,
}: {
  summaryId: string;
  parts?: Card[];
  from?: number;
  small?: boolean;
}) {
  const hydrated = useHydrated();
  const { api } = useAuth();
  const { player, state } = useListen();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!hydrated || !player) return null;
  if (parts && !parts.some((c) => player.canPlay(c))) return null;

  const queue = `summary:${summaryId}`;
  const current = state.active && state.queue === queue && state.phase !== "finished";
  const playing = current && state.playing;

  async function press() {
    if (!player || busy) return;
    if (current) {
      player.toggle();
      return;
    }
    let cards = parts;
    if (!cards) {
      setBusy(true);
      setError(null);
      try {
        cards = (await api.summary(summaryId)).parts;
      } catch (err) {
        setError(isApiError(err) ? err.message : "Couldn't load this summary.");
        return;
      } finally {
        setBusy(false);
      }
    }
    player.playCards(cards, { queue, index: Math.max(0, Math.min(cards.length - 1, from)) });
  }

  return (
    <>
      <button
        type="button"
        className={`btn ${small ? "btn-small" : ""}`}
        onClick={press}
        aria-pressed={playing}
        disabled={busy}
      >
        <Icon name={playing ? "pause" : "headphones"} className="size-4" />
        {playing ? "Pause" : current ? "Resume" : busy ? "Loading…" : "Listen"}
      </button>
      {error ? (
        <span role="alert" className="text-sm text-bad">
          {error}
        </span>
      ) : null}
    </>
  );
}

/**
 * A summary post in the timeline or a list: its cover, what it is, where the reader got to, and
 * Start reading / Continue (one part per screen), Read it all (one long page) and Listen.
 * With `snap` it fills a slide of the phone feed.
 */
export function SummaryPost({ summary, snap = false }: { summary: Summary; snap?: boolean }) {
  const hydrated = useHydrated();
  const progress = bestProgress(summary.viewer, hydrated ? localProgress(summary.id) : null);
  const from = resumeIndex(progress, summary.part_count);
  const continuing = !!progress?.started && !progress.finished && from > 0;
  const href = summaryHref(summary.id, { part: continuing ? from + 1 : undefined });

  return (
    <article
      aria-labelledby={`summary-${summary.id}-title`}
      data-summary-id={summary.id}
      className={`panel px-5 py-6 sm:px-8 sm:py-8 ${
        snap ? "max-md:flex max-md:h-full max-md:flex-col max-md:justify-center max-md:px-4 max-md:py-4" : ""
      }`}
    >
      <div className="mx-auto w-full max-w-read">
        <SummaryCover summary={summary} href={href} size={snap ? "large" : "small"} />
        <p className="mt-4 text-[0.9375rem] leading-relaxed text-fg-2 max-md:line-clamp-3">{summary.description}</p>
        {progress?.started ? (
          <div className="mt-4">
            <SummaryProgressBar progress={progress} parts={summary.part_count} />
          </div>
        ) : null}
        <div className="mt-5 flex flex-wrap items-center gap-2">
          <Link href={href} className="btn btn-primary btn-small">
            <Icon name="arrowForward" className="size-4" />
            {continuing ? "Continue" : progress?.finished ? "Read again" : "Start reading"}
            <span className="sr-only">: {summary.title}</span>
          </Link>
          <Link href={summaryHref(summary.id, { view: "all" })} className="btn btn-small">
            <Icon name="notes" className="size-4" />
            Read it all
          </Link>
          <ListenSummaryButton summaryId={summary.id} from={from} />
          <ShareMenu
            path={summaryHref(summary.id)}
            title={summary.title}
            what={summary.coverage === "guide" ? "guide" : "summary"}
          />
        </div>
      </div>
    </article>
  );
}
