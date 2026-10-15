import type { Metadata } from "next";
import { MyCardsView } from "./MyCardsView";

export const metadata: Metadata = { title: "My cards", robots: { index: false, follow: false } };

export default function Page() {
  return <MyCardsView />;
}
