import { resumeIndex, summaryHref } from "./summaries";
import type { Subject, SubjectProgress, Summary, SummaryProgress } from "./types";

/*
 * Subjects: short courses of guides, followed one after the other. Each guide is a summary, read
 * in the summary reader, so how far a reader is through a subject comes from their summary
 * progress: the API's when signed in, this browser's otherwise.
 */

export function subjectHref(id: string): string {
  return `/subjects/${encodeURIComponent(id)}`;
}

/** "7 guides · 60 min". */
export function subjectMeta(s: Pick<Subject, "guide_count" | "minutes">): string {
  return `${s.guide_count} ${s.guide_count === 1 ? "guide" : "guides"} · ${s.minutes} min`;
}

/** "3 of 7 done", or null when the reader hasn't started (or is signed out). */
export function subjectProgressLabel(viewer: SubjectProgress | null | undefined, count: number): string | null {
  if (!viewer || (!viewer.started && viewer.finished === 0)) return null;
  return `${Math.min(viewer.finished, count)} of ${count} done`;
}

export type GuideState = "done" | "in-progress" | "not-started";

export function guideState(p: SummaryProgress | null | undefined): GuideState {
  if (p?.finished) return "done";
  if (p?.started) return "in-progress";
  return "not-started";
}

export interface SubjectPlan {
  /** "Start" (nothing read yet), "Continue" (to the next unfinished guide) or "Read again" (all done). */
  action: "start" | "continue" | "again";
  guide: Summary;
  href: string;
  /** Guides finished. */
  finished: number;
}

/**
 * What the subject's main button does, from each guide's progress: the first guide when nothing
 * is read yet or everything is done, else the first unfinished guide, opened where the reader
 * stopped in it.
 */
export function subjectPlan(
  guides: Summary[],
  progressOf: (g: Summary) => SummaryProgress | null | undefined,
): SubjectPlan | null {
  if (!guides.length) return null;
  const states = guides.map((g) => guideState(progressOf(g)));
  const finished = states.filter((s) => s === "done").length;
  if (finished === guides.length) {
    return { action: "again", guide: guides[0], href: summaryHref(guides[0].id), finished };
  }
  if (states.every((s) => s === "not-started")) {
    return { action: "start", guide: guides[0], href: summaryHref(guides[0].id), finished };
  }
  const i = states.findIndex((s) => s !== "done");
  const guide = guides[i];
  const from = resumeIndex(progressOf(guide) ?? null, guide.part_count);
  return { action: "continue", guide, href: summaryHref(guide.id, { part: from + 1 }), finished };
}
