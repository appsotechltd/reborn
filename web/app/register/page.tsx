import type { Metadata } from "next";
import { AuthForm } from "@/components/AuthForm";
import { safeNext } from "@/lib/safe-next";

export const metadata: Metadata = {
  title: "Create an account",
  alternates: { canonical: "/register" },
  robots: { index: false, follow: true },
};

export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { next, ref } = await searchParams;
  return <AuthForm mode="register" next={safeNext(next)} referral={(Array.isArray(ref) ? ref[0] : ref) ?? undefined} />;
}
