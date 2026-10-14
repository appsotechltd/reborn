import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SummaryCover } from "@/components/SummaryPost";
import { SummaryReader, type SummaryView } from "@/components/SummaryReader";
import { Unavailable } from "@/components/Unavailable";
import { getSitemap, getSummary, loadOr } from "@/lib/server-api";
import { coverageLabel, summaryByline } from "@/lib/summaries";

export const revalidate = 600;

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(v: string | string[] | undefined): string {
  return (Array.isArray(v) ? v[0] : v)?.trim() ?? "";
}

export async function generateStaticParams() {
  try {
    const sitemap = await getSitemap();
    return (sitemap.summaries ?? []).slice(0, 200).map((s) => ({ id: s.id }));
  } catch {
    return [];
  }
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const { data } = await loadOr(() => getSummary(id), null);
  if (!data) return { title: "Summary not found", robots: { index: false } };
  const title = `${data.title}: ${coverageLabel(data).toLowerCase()}`;
  const by = summaryByline(data);
  const description = `${data.description} ${data.part_count} one-minute parts${by ? `, ${by}` : ""}.`;
  const url = `/summaries/${data.id}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { siteName: "Reborn", type: "article", title, description, url },
    twitter: { card: "summary", title, description },
  };
}

export default async function SummaryPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const [{ id }, sp] = await Promise.all([params, searchParams]);
  const { data, ok } = await loadOr(() => getSummary(id), null);
  if (!ok) return <Unavailable what="this summary" />;
  if (!data || data.parts.length === 0) notFound();
  const view: SummaryView = first(sp.view) === "all" ? "all" : "parts";
  const part = Number.parseInt(first(sp.part), 10);
  const initialPart = Number.isFinite(part) && part >= 1 ? Math.min(part, data.parts.length) - 1 : null;

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mx-auto max-w-read">
        <SummaryCover summary={data} headingLevel="h1" />
        <p className="mt-4 text-lg leading-relaxed text-fg-2">{data.description}</p>
        {data.source ? (
          <p className="mt-2 text-sm text-muted">
            From{" "}
            <Link href={`/sources/${data.source.id}`} className="link">
              {data.source.title}
            </Link>
            {data.coverage === "key-ideas"
              ? ". These are our own summaries; read the book for the full work."
              : ", with its credit and licence."}
          </p>
        ) : (
          <p className="mt-2 text-sm text-muted">Each part links to the book it comes from.</p>
        )}
      </header>
      <div className="mt-6">
        <SummaryReader key={data.id} summary={data} initialView={view} initialPart={initialPart} />
      </div>
    </div>
  );
}
