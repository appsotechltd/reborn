import type { Metadata } from "next";
import { AskView } from "./AskView";

export const metadata: Metadata = {
  title: "Ask the guide",
  description: "Ask questions answered only from the Reborn library, with links to every idea cited.",
  robots: { index: false, follow: true },
};

export default function Page() {
  return <AskView />;
}
