import type { Metadata } from "next";
import { ResetPasswordForm } from "./ResetPasswordForm";

export const metadata: Metadata = {
  title: "Choose a new password",
  alternates: { canonical: "/reset-password" },
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { token } = await searchParams;
  return <ResetPasswordForm token={(Array.isArray(token) ? token[0] : token) ?? ""} />;
}
