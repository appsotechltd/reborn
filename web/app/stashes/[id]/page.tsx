import type { Metadata } from "next";
import { StashDetail } from "./StashDetail";

export const metadata: Metadata = { title: "Stash", robots: { index: false, follow: false } };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <StashDetail id={id} />;
}
