import type { Metadata } from "next";
import { ReviewView } from "./ReviewView";

export const metadata: Metadata = { title: "Review", robots: { index: false, follow: false } };

export default function Page() {
  return <ReviewView />;
}
