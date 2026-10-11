import type { Metadata } from "next";
import { PremiumView } from "./PremiumView";

const description = "Reborn Premium: ten times the AI guide's hourly limit, and you help keep the library free for everyone.";

export const metadata: Metadata = {
  title: "Premium",
  description,
  alternates: { canonical: "/premium" },
  openGraph: { siteName: "Reborn", title: "Reborn Premium", description, url: "/premium" },
};

export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { welcome } = await searchParams;
  return <PremiumView welcome={welcome === "1"} />;
}
