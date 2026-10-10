import type { Metadata } from "next";
import { ContributeView } from "./ContributeView";

export const metadata: Metadata = {
  title: "Contribute an idea",
  description: "Share an idea from a book or article in your own words.",
  robots: { index: false, follow: true },
};

export default function Page() {
  return <ContributeView />;
}
