import type { Metadata } from "next";
import { StashesView } from "./StashesView";

export const metadata: Metadata = { title: "Your collections", robots: { index: false, follow: false } };

export default function Page() {
  return <StashesView />;
}
