import type { Metadata } from "next";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { Timeline } from "@/components/Timeline";
import { Unavailable } from "@/components/Unavailable";
import { TOPICS } from "@/lib/content";
import { SITE_NAME, SITE_TAGLINE, siteUrl } from "@/lib/config";
import { getTimeline, getTopics, loadOr } from "@/lib/server-api";
import type { TimelineResponse, Topic } from "@/lib/types";

export const revalidate = 600;

export const metadata: Metadata = {
  title: { absolute: `${SITE_NAME}: ${SITE_TAGLINE}` },
  alternates: { canonical: "/" },
  openGraph: {
    siteName: "Reborn",
    title: SITE_NAME,
    description: SITE_TAGLINE,
    url: "/",
  },
  twitter: { card: "summary_large_image", title: SITE_NAME, description: SITE_TAGLINE },
};

export default async function HomePage() {
  // The anonymous first page is rendered on the server so crawlers and
  // signed-out visitors get real content; signed-in readers then get their own.
  const { data, ok } = await loadOr(
    async () => {
      const [timeline, topics] = await Promise.all([getTimeline(10), getTopics()]);
      return { timeline, topics };
    },
    null as null | { timeline: TimelineResponse; topics: Topic[] },
  );
  const topics: Topic[] = data?.topics ?? TOPICS.map((t) => ({ ...t, card_count: 0 }));

  return (
    <div className="space-y-10 max-md:-mt-4 max-md:space-y-0">
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "WebSite",
          name: SITE_NAME,
          url: siteUrl(),
          potentialAction: {
            "@type": "SearchAction",
            target: `${siteUrl()}/search?q={search_term_string}`,
            "query-input": "required name=search_term_string",
          },
        }}
      />
      {/* On phones the feed starts straight under the header, as in the app; the heading stays for screen readers. */}
      <section aria-labelledby="hero-title" className="mx-auto max-w-read text-center max-md:sr-only">
        <h1 id="hero-title" className="font-serif text-2xl font-semibold tracking-tight text-balance sm:text-4xl">
          Big ideas, one minute at a time.
        </h1>
        <p className="mt-2 text-muted text-pretty sm:mt-3">
          Short idea cards from great books and open sources, each credited to where it came from.
        </p>
      </section>

      {/* On phones the timeline's own topic chips filter the feed in place instead, as in the app. */}
      <nav aria-label="Topics" className="mx-auto max-w-3xl max-md:hidden">
        <ul className="flex flex-wrap justify-center gap-2">
          {topics.map((t) => (
            <li key={t.slug} className="shrink-0">
              <Link href={`/topics/${t.slug}`} className="chip min-h-8 hover:text-fg pointer-coarse:min-h-11">
                {t.name}
              </Link>
            </li>
          ))}
        </ul>
      </nav>

      {ok && data ? (
        <Timeline initialPosts={data.timeline.posts} initialCursor={data.timeline.next_cursor} topics={topics} />
      ) : (
        <Unavailable what="the timeline" />
      )}
    </div>
  );
}
