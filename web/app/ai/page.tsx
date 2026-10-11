import type { Metadata } from "next";
import { AIView } from "./AIView";

export const metadata: Metadata = {
  title: "Reborn AI",
  description: "Reborn AI: a premium assistant you can talk or type to, grounded in the Reborn library, with charts and pictures.",
  robots: { index: false, follow: true },
};

export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { topup } = await searchParams;
  return <AIView topup={typeof topup === "string" ? topup : null} />;
}
