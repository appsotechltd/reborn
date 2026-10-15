import type { Metadata } from "next";
import { NewCardView } from "../CardEditor";

export const metadata: Metadata = { title: "Write a card", robots: { index: false, follow: false } };

export default function Page() {
  return <NewCardView />;
}
