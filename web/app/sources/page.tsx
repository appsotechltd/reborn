import type { Metadata } from "next";
import Link from "next/link";
import { Unavailable } from "@/components/Unavailable";
import { formatAuthors, licenceName, topicName } from "@/lib/content";
import { getAllSources, loadOr } from "@/lib/server-api";

export const revalidate = 600;

const description = "Every book, textbook, guide and article in the Reborn library, with its licence and idea cards.";

export const metadata: Metadata = {
  title: "All sources",
  description,
  alternates: { canonical: "/sources" },
  openGraph: { siteName: "Reborn", title: "All sources", description, url: "/sources" },
  twitter: { card: "summary", title: "All sources", description },
};

export default async function SourcesPage() {
  const { data: sources, ok } = await loadOr(() => getAllSources(), []);
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-4xl font-semibold tracking-tight">Sources</h1>
      <p className="mt-3 text-lg text-muted">
        Every idea on Reborn comes from one of these works and links back to it.
      </p>
      {!ok ? (
        <div className="mt-8">
          <Unavailable what="the sources" />
        </div>
      ) : sources.length === 0 ? (
        <p className="mt-8 text-muted">No sources have been published yet.</p>
      ) : (
        <ul className="mt-8 divide-y divide-line border-y border-line">
          {sources.map((s) => (
            <li key={s.id} className="py-5">
              <h2 className="font-serif text-xl font-semibold">
                <Link href={`/sources/${s.id}`} className="hover:underline">
                  {s.title}
                </Link>
              </h2>
              <p className="mt-1 text-muted">
                {formatAuthors(s.authors)} · <span className="capitalize">{s.kind}</span> · {licenceName(s.licence)}
              </p>
              <p className="mt-2 flex flex-wrap items-center gap-2 text-sm">
                <span className="text-muted">
                  {s.card_count} {s.card_count === 1 ? "idea" : "ideas"}
                </span>
                {s.topics.map((t) => (
                  <Link key={t} href={`/topics/${t}`} className="chip hover:text-fg">
                    {topicName(t)}
                  </Link>
                ))}
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
