import type { Metadata } from "next";
import { Suspense } from "react";
import { Loading } from "@/components/SignInPrompt";
import { CirclesView } from "./CirclesView";

const description = "Book circles: small groups of up to 50 readers discussing one book together on Reborn.";

export const metadata: Metadata = {
  title: "Book circles",
  description,
  alternates: { canonical: "/circles" },
  openGraph: { siteName: "Reborn", title: "Book circles", description, url: "/circles" },
};

export default function Page() {
  return (
    <Suspense fallback={<Loading />}>
      <CirclesView />
    </Suspense>
  );
}
