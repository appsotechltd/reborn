import type { Metadata } from "next";
import { ForgotPasswordForm } from "./ForgotPasswordForm";

export const metadata: Metadata = {
  title: "Forgot password",
  alternates: { canonical: "/forgot-password" },
  robots: { index: false, follow: true },
};

export default function Page() {
  return <ForgotPasswordForm />;
}
