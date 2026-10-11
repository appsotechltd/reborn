import type { Metadata } from "next";
import { JoinView } from "./JoinView";

export const metadata: Metadata = {
  title: "You're invited",
  description: "A friend invited you to Reborn: big ideas from great books, one minute at a time.",
  alternates: { canonical: "/join" },
  robots: { index: false, follow: true },
};

export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { ref } = await searchParams;
  return <JoinView code={(Array.isArray(ref) ? ref[0] : ref) ?? ""} />;
}
