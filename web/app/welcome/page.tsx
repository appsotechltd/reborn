import type { Metadata } from "next";
import { safeNext } from "@/lib/safe-next";
import { WelcomeView } from "./WelcomeView";

export const metadata: Metadata = { title: "Pick your topics", robots: { index: false, follow: false } };

/**
 * The topic picker, as in the app (topic_picker_screen.dart). New accounts land here
 * straight after sign-up; Settings and the end of the feed open it with `?edit=1`.
 */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { next, edit } = await searchParams;
  return <WelcomeView next={safeNext(next)} onboarding={!edit} />;
}
