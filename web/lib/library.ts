import { TOPICS } from "./content";

export type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(v: string | string[] | undefined): string {
  return (Array.isArray(v) ? v[0] : v)?.trim() ?? "";
}

/** The Library's filters from the URL (?q=&topic=), an unknown topic ignored. */
export async function libraryFilters(searchParams: SearchParams): Promise<{ q: string; topic: string }> {
  const sp = await searchParams;
  const topic = first(sp.topic);
  return { q: first(sp.q).slice(0, 100), topic: TOPICS.some((t) => t.slug === topic) ? topic : "" };
}
