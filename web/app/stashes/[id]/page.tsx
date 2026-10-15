import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isUuid } from "@/lib/content";
import { getPublicStash, loadOr } from "@/lib/server-api";
import { StashDetail } from "./StashDetail";

export const metadata: Metadata = { title: "Collection", robots: { index: false, follow: false } };

/**
 * A stash is private to its owner, and the owner's session lives in the browser, so the
 * server can only rule out ids that can't exist (a real 404). For a well-formed id a
 * signed-out visitor gets a sign-in prompt (it may be theirs, and saying "not found"
 * would be wrong); if the owner has made it public, the prompt links to its public page.
 */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound(); // stash ids are UUIDs: anything else can't be one, for anyone
  const { data: shared } = await loadOr(() => getPublicStash(id), null);
  return <StashDetail id={id} publicHref={shared ? `/s/${shared.stash.id}` : undefined} />;
}
