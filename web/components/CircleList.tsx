import Link from "next/link";
import type { Circle } from "@/lib/types";

/** Grid of book circles linking to /circles/[id]. */
export function CircleList({ circles, showBook = true }: { circles: Circle[]; showBook?: boolean }) {
  return (
    <ul className="grid gap-4 sm:grid-cols-2">
      {circles.map((c) => (
        <li key={c.id} className="panel relative p-5 transition-colors hover:border-accent focus-within:border-accent">
          {showBook ? <p className="eyebrow truncate">{c.source.title}</p> : null}
          <h3 className="mt-1 font-serif text-xl font-semibold leading-snug">
            <Link href={`/circles/${c.id}`} className="after:absolute after:inset-0 hover:underline focus-visible:outline-none">
              {c.name}
            </Link>
          </h3>
          {c.description ? <p className="mt-1 line-clamp-2 text-sm text-muted">{c.description}</p> : null}
          <p className="mt-2 text-xs text-muted">
            {c.members} {c.members === 1 ? "member" : "members"}
            {c.is_member ? " · You're in" : ""}
          </p>
        </li>
      ))}
    </ul>
  );
}
