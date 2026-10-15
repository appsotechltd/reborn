import type { Metadata } from "next";
import { EarningsView } from "./EarningsView";

export const metadata: Metadata = { title: "Earnings", robots: { index: false, follow: false } };

export default function Page() {
  return <EarningsView />;
}
