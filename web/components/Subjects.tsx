"use client";

import Link from "next/link";
import { useCallback } from "react";
import { useAuth, useHydrated } from "@/lib/auth";
import { guideState, subjectHref, subjectMeta, subjectPlan, subjectProgressLabel, type GuideState } from "@/lib/subjects";
import { bestProgress, localProgress, summaryHref, summaryMeta } from "@/lib/summaries";
import type { Subject, SubjectDetail, SubjectStep, Summary, SummaryProgress } from "@/lib/types";
import { useLoad } from "@/lib/use-load";
import { Icon } from "./Icon";

/**
 * A subject's cover, in the same always-dark Candlelight look as a summary's: the first guide's
 * picture behind the title, darkened so it stays readable.
 */
export function SubjectCover({
  subject,
  headingLevel = "h3",
  href,
  size = "small",
}: {
  subject: Subject;
  headingLevel?: "h1" | "h2" | "h3";
  href?: string;
  size?: "large" | "small";
}) {
  const Heading = headingLevel;
  return (
    <div
      className="relative overflow-hidden rounded-inset bg-[#1f1710] px-5 py-6 text-[#f2e8d8] sm:px-7 sm:py-8"
      style={{
        backgroundImage: subject.cover
          ? `linear-gradient(to top, rgba(31,23,16,0.96) 30%, rgba(31,23,16,0.55)), url("${subject.cover.url}")`
          : "radial-gradient(120% 90% at 85% 0%, rgba(233,162,59,0.28), transparent 60%)",
        backgroundSize: "cover",
        backgroundPosition: "center",
      }}
      data-subject-cover
    >
      {subject.cover ? (
        <span role="img" aria-label={subject.cover.caption} className="sr-only" data-subject-cover-image />
      ) : null}
      {subject.cover ? <div aria-hidden="true" className={size === "large" ? "h-24 sm:h-36" : "h-16"} /> : null}
      <p className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-[0.12em] text-[#e9a23b]">
        <Icon name="libraryBooks" className="size-4" />
        <span>Subject</span>
      </p>
      <Heading
        id={`subject-${subject.id}-title`}
        className={`mt-3 font-serif font-semibold leading-tight tracking-tight text-balance ${
          size === "large" ? "text-3xl sm:text-4xl" : "text-2xl"
        }`}
      >
        {href ? (
          <Link href={href} className="after:absolute after:inset-0 hover:underline">
            {subject.title}
          </Link>
        ) : (
          subject.title
        )}
      </Heading>
      <p className="mt-4 inline-flex items-center gap-1.5 rounded-full border border-[#4a3e32] px-3 py-1 text-xs font-semibold text-[#f2e8d8]">
        {subjectMeta(subject)}
      </p>
    </div>
  );
}

/** "Guide 2 of 7 · Communication Clarity" above a guide, linking to its subject. */
export function SubjectStepLink({ step }: { step: SubjectStep }) {
  return (
    <p className="mb-3 text-sm font-semibold text-accent-text" data-subject-step>
      <Link href={subjectHref(step.id)} className="hover:underline">
        Guide {step.step} of {step.count} · {step.title}
      </Link>
    </p>
  );
}

/** "3 of 7 done" with a bar. */
function SubjectProgressBar({ finished, count }: { finished: number; count: number }) {
  const done = Math.min(finished, count);
  return (
    <div className="flex items-center gap-3 text-sm text-muted" data-subject-progress>
      <div
        className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2"
        role="progressbar"
        aria-label="Guides done"
        aria-valuemin={0}
        aria-valuemax={count}
        aria-valuenow={done}
      >
        <div className="h-full rounded-full bg-accent" style={{ width: `${(done / Math.max(1, count)) * 100}%` }} />
      </div>
      <span className="shrink-0">{`${done} of ${count} done`}</span>
    </div>
  );
}

/** A subject in a list: its cover, what it covers, and how far the signed-in reader is. */
export function SubjectCard({ subject }: { subject: Subject }) {
  const progress = subjectProgressLabel(subject.viewer, subject.guide_count);
  return (
    <article aria-labelledby={`subject-${subject.id}-title`} data-subject-id={subject.id} className="panel relative h-full p-3">
      <SubjectCover subject={subject} href={subjectHref(subject.id)} />
      <p className="mt-3 px-1 text-[0.9375rem] leading-relaxed text-fg-2 line-clamp-3">{subject.description}</p>
      {progress && subject.viewer ? (
        <div className="mt-3 px-1 pb-1">
          <SubjectProgressBar finished={subject.viewer.finished} count={subject.guide_count} />
        </div>
      ) : null}
    </article>
  );
}

/**
 * A topic's subjects, above its ideas. The page renders them signed out; a signed-in reader's
 * progress is filled in from the API.
 */
export function SubjectList({ subjects, topic }: { subjects: Subject[]; topic: string }) {
  const { token, api } = useAuth();
  const loader = useCallback(() => api.subjects({ topic }), [api, topic]);
  const { data } = useLoad(token ? loader : null);
  const shown = data?.length ? data : subjects;
  if (!shown.length) return null;
  return (
    <section aria-labelledby="subjects-title" className="mt-10">
      <h2 id="subjects-title" className="font-serif text-2xl font-semibold">
        Subjects
      </h2>
      <p className="mt-1 text-muted">Short courses: guides to follow one after the other.</p>
      <ul className="mt-4 grid gap-4 sm:grid-cols-2">
        {shown.map((s) => (
          <li key={s.id}>
            <SubjectCard subject={s} />
          </li>
        ))}
      </ul>
    </section>
  );
}

const STATE_LABEL: Record<GuideState, string> = {
  done: "Done",
  "in-progress": "In progress",
  "not-started": "Not started",
};

/**
 * A subject's guides in order, each marked done, in progress or not started, under the main
 * button: Start, Continue with the next guide, or Read again. Progress is the API's when signed
 * in, this browser's otherwise.
 */
export function SubjectGuides({ subject }: { subject: SubjectDetail }) {
  const hydrated = useHydrated();
  const { token, api } = useAuth();
  const loader = useCallback(() => api.subject(subject.id), [api, subject.id]);
  const { data } = useLoad(token ? loader : null);
  const guides = data?.guides.length ? data.guides : subject.guides;
  const progressOf = (g: Summary): SummaryProgress | null =>
    bestProgress(g.viewer, hydrated ? localProgress(g.id) : null);
  const plan = subjectPlan(guides, progressOf);
  if (!plan) return <p className="mt-6 text-muted">The guides in this subject are on their way.</p>;

  const label =
    plan.action === "start" ? "Start" : plan.action === "again" ? "Read again" : `Continue: ${plan.guide.title}`;

  return (
    <div data-subject-guides>
      <div className="mx-auto mt-6 max-w-read">
        {plan.finished > 0 || plan.action === "continue" ? (
          <div className="mb-4">
            <SubjectProgressBar finished={plan.finished} count={guides.length} />
          </div>
        ) : null}
        <Link href={plan.href} className="btn btn-primary w-full justify-center sm:w-auto">
          <Icon name="arrowForward" className="size-5" />
          <span className="min-w-0 truncate">{label}</span>
        </Link>
      </div>

      <section aria-labelledby="guides-title" className="mx-auto mt-10 max-w-read">
        <h2 id="guides-title" className="font-serif text-2xl font-semibold">
          {guides.length} {guides.length === 1 ? "guide" : "guides"}, in order
        </h2>
        <ol className="mt-4 grid gap-3">
          {guides.map((g, i) => {
            const p = progressOf(g);
            const state = guideState(p);
            const resume = state === "in-progress" && p ? Math.min(g.part_count, p.position + 1) : 0;
            return (
              <li key={g.id} data-guide-state={state}>
                <Link
                  href={summaryHref(g.id, { part: resume > 1 ? resume : undefined })}
                  className={`panel flex items-start gap-4 px-4 py-4 hover:border-accent ${
                    plan.action === "continue" && plan.guide.id === g.id ? "border-accent" : ""
                  }`}
                >
                  <span
                    aria-hidden="true"
                    className={`mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold ${
                      state === "done"
                        ? "bg-accent text-accent-fg"
                        : state === "in-progress"
                          ? "border-2 border-accent text-accent-text"
                          : "border border-line text-muted"
                    }`}
                  >
                    {state === "done" ? <Icon name="check" className="size-5" /> : i + 1}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="sr-only">Guide {i + 1}: </span>
                    <span className="block font-semibold leading-snug">{g.title}</span>
                    <span className="mt-1 block text-sm text-muted">
                      {summaryMeta(g)}
                      <span aria-hidden="true"> · </span>
                      <span className={state === "not-started" ? "" : "font-semibold text-accent-text"}>
                        <span className="sr-only">, </span>
                        {state === "in-progress" && resume ? `In progress, part ${resume} of ${g.part_count}` : STATE_LABEL[state]}
                      </span>
                    </span>
                  </span>
                  <Icon name="chevronRight" className="mt-2 size-5 text-muted" />
                </Link>
              </li>
            );
          })}
        </ol>
      </section>
    </div>
  );
}
