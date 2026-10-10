import Link from "next/link";
import { parseCitations } from "@/lib/citations";
import { paragraphs } from "@/lib/content";
import type { Card } from "@/lib/types";

/** Renders an agent reply, turning inline `[card-id]` citations into links to the cards. */
export function CitedText({ text, citations }: { text: string; citations: Card[] }) {
  return (
    <>
      {paragraphs(text).map((para, pi) => (
        <p key={pi} className="whitespace-pre-line [&+p]:mt-3">
          {parseCitations(para, citations).map((seg, i) =>
            seg.type === "text" ? (
              <span key={i}>{seg.text}</span>
            ) : (
              <Link
                key={i}
                href={`/ideas/${seg.id}`}
                className="mx-0.5 inline-flex min-w-6 items-center justify-center rounded-md bg-accent-soft px-1.5 align-baseline text-sm font-semibold text-fg no-underline hover:underline"
                title={seg.card ? seg.card.title : seg.id}
                aria-label={`Source ${seg.index}: ${seg.card ? seg.card.title : seg.id}`}
              >
                {seg.index}
              </Link>
            ),
          )}
        </p>
      ))}
    </>
  );
}
