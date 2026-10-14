import { formatAuthors } from "./content";
import type { Summary, SummaryProgress } from "./types";

/*
 * Full summary posts: one post for a whole book or topic, read one part (card) at a time, or all
 * on one page, or listened to start to finish. A signed-in reader's place is kept by the API; a
 * signed-out reader's in this browser.
 */

/** The label above a summary's title. */
export function coverageLabel(s: Pick<Summary, "coverage">): string {
  switch (s.coverage) {
    case "key-ideas":
      return "Key ideas summary";
    case "topic":
      return "Topic summary";
    default:
      return "Full summary";
  }
}

/** "by Robert Greene", or for a topic "From 6 books, including Seneca, the NHS and …". */
export function summaryByline(s: Pick<Summary, "kind" | "authors" | "source_count">): string {
  if (s.kind === "book") return s.authors.length ? `by ${formatAuthors(s.authors)}` : "";
  const books = `From ${s.source_count} ${s.source_count === 1 ? "source" : "sources"}`;
  const names = s.authors.slice(0, 2);
  if (!names.length) return books;
  return `${books}, including ${formatAuthors(s.authors.length > 2 ? [...names, "more"] : names)}`;
}

/** "30 parts · 18 min". */
export function summaryMeta(s: Pick<Summary, "part_count" | "minutes">): string {
  return `${s.part_count} ${s.part_count === 1 ? "part" : "parts"} · ${s.minutes} min`;
}

/** The reader's page; `part` is one-based, `view` "all" for the one long page. */
export function summaryHref(id: string, opts: { part?: number; view?: "all" } = {}): string {
  const q = new URLSearchParams();
  if (opts.view) q.set("view", opts.view);
  if (opts.part && opts.part > 1) q.set("part", String(opts.part));
  const qs = q.toString();
  return `/summaries/${encodeURIComponent(id)}${qs ? `?${qs}` : ""}`;
}

// --- This browser's place in each summary (signed-out readers, and a fallback) -------------------

const KEY = "reborn.summaries";

type Saved = Record<string, SummaryProgress>;

function readAll(): Saved {
  try {
    const raw = window.localStorage.getItem(KEY);
    const v: unknown = raw ? JSON.parse(raw) : null;
    return v && typeof v === "object" ? (v as Saved) : {};
  } catch {
    return {};
  }
}

export function localProgress(id: string): SummaryProgress | null {
  if (typeof window === "undefined") return null;
  const p = readAll()[id];
  return p && typeof p.position === "number" ? p : null;
}

/** Keeps the place; finishing sticks, so rereading a part doesn't undo it. */
export function saveLocalProgress(id: string, position: number, finished: boolean): SummaryProgress {
  const all = readAll();
  const p: SummaryProgress = { started: true, position, finished: finished || !!all[id]?.finished };
  all[id] = p;
  try {
    window.localStorage.setItem(KEY, JSON.stringify(all));
  } catch {
    // Private mode or full storage: the place just isn't kept.
  }
  return p;
}

/** The furthest-along place we know of: the API's for a signed-in reader, else this browser's. */
export function bestProgress(server: SummaryProgress | null | undefined, local: SummaryProgress | null): SummaryProgress | null {
  if (server?.started) return server;
  return local;
}

/** Where "Continue" opens: the saved part, or the start once finished. */
export function resumeIndex(p: SummaryProgress | null, parts: number): number {
  if (!p || !p.started || p.finished) return 0;
  return Math.max(0, Math.min(parts - 1, p.position));
}
