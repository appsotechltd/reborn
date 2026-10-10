import type { Metadata } from "next";
import { ModerationView } from "./ModerationView";

export const metadata: Metadata = { title: "Moderation", robots: { index: false, follow: false } };

export default function Page() {
  return <ModerationView />;
}
