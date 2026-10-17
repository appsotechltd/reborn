import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { breadcrumbsJsonLd, JsonLd } from "@/components/JsonLd";
import { ShareMenu } from "@/components/ShareMenu";
import { SubjectCover, SubjectGuides } from "@/components/Subjects";
import { Unavailable } from "@/components/Unavailable";
import { topicName } from "@/lib/content";
import { siteUrl } from "@/lib/config";
import { getSubject, getSubjects, loadOr } from "@/lib/server-api";
import { subjectHref, subjectMeta } from "@/lib/subjects";

export const revalidate = 600;

export async function generateStaticParams() {
  try {
    return (await getSubjects()).map((s) => ({ id: s.id }));
  } catch {
    return [];
  }
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params;
  const { data } = await loadOr(() => getSubject(id), null);
  if (!data) return { title: "Subject not found", robots: { index: false } };
  const title = `${data.title}: a ${data.guide_count}-guide course`;
  const description = `${data.description} ${subjectMeta(data)}, one guide after the other.`;
  const url = subjectHref(data.id);
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: { siteName: "Reborn", type: "website", title, description, url },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function SubjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data, ok } = await loadOr(() => getSubject(id), null);
  if (!ok) return <Unavailable what="this subject" />;
  if (!data) notFound();

  const base = siteUrl();
  const path = subjectHref(data.id);
  const url = `${base}${path}`;
  const topic = data.topics[0];

  return (
    <div className="mx-auto max-w-3xl">
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "Course",
          "@id": url,
          url,
          name: data.title,
          description: data.description,
          image: `${url}/opengraph-image`,
          inLanguage: "en",
          isAccessibleForFree: true,
          timeRequired: `PT${data.minutes}M`,
          provider: { "@type": "Organization", name: "Reborn", url: base },
          hasPart: data.guides.map((g, i) => ({
            "@type": "Article",
            position: i + 1,
            headline: g.title,
            url: `${base}/summaries/${g.id}`,
          })),
        }}
      />
      <JsonLd
        data={breadcrumbsJsonLd(base, [
          ...(topic ? [[topicName(topic), `/topics/${topic}`] as [string, string]] : []),
          [data.title, path],
        ])}
      />
      <header className="mx-auto max-w-read">
        {topic ? (
          <nav aria-label="Breadcrumb" className="mb-3 text-sm text-muted">
            <Link href={`/topics/${topic}`} className="link">
              {topicName(topic)}
            </Link>
            <span aria-hidden="true"> / </span>
            <span>Subject</span>
          </nav>
        ) : null}
        <SubjectCover subject={data} headingLevel="h1" size="large" />
        <p className="mt-4 text-lg leading-relaxed text-fg-2">{data.description}</p>
        <p className="mt-2 text-sm text-muted">
          {subjectMeta(data)}. Follow the guides in order, one after the other.
        </p>
        <div className="mt-3">
          <ShareMenu path={path} title={data.title} what="subject" label />
        </div>
      </header>
      <SubjectGuides subject={data} />
    </div>
  );
}
