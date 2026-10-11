import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/config";
import { TOPICS } from "@/lib/content";
import { getAllAuthors, getSitemap, loadOr } from "@/lib/server-api";
import { authorHref } from "@/lib/social";

export const revalidate = 600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const base = siteUrl();
  const [{ data }, { data: authors }] = await Promise.all([loadOr(getSitemap, null), loadOr(() => getAllAuthors(), [])]);
  const topics = data?.topics ?? TOPICS.map((t) => t.slug);
  const latest = (items: { updated_at: string }[]) =>
    items.reduce<string | undefined>((m, i) => (!m || i.updated_at > m ? i.updated_at : m), undefined);

  return [
    { url: `${base}/`, changeFrequency: "daily", priority: 1, lastModified: latest(data?.cards ?? []) },
    { url: `${base}/sources`, changeFrequency: "weekly", priority: 0.6, lastModified: latest(data?.sources ?? []) },
    { url: `${base}/authors`, changeFrequency: "weekly", priority: 0.6 },
    ...topics.map((t) => ({ url: `${base}/topics/${t}`, changeFrequency: "weekly" as const, priority: 0.7 })),
    ...(data?.sources ?? []).map((s) => ({
      url: `${base}/sources/${s.id}`,
      lastModified: s.updated_at,
      changeFrequency: "monthly" as const,
      priority: 0.6,
    })),
    ...authors.map((a) => ({
      url: `${base}${authorHref(a.name)}`,
      changeFrequency: "weekly" as const,
      priority: 0.5,
    })),
    ...(data?.cards ?? []).map((c) => ({
      url: `${base}/ideas/${c.id}`,
      lastModified: c.updated_at,
      changeFrequency: "monthly" as const,
      priority: 0.8,
    })),
  ];
}
