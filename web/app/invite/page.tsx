import type { Metadata } from "next";
import { InviteView } from "./InviteView";

export const metadata: Metadata = { title: "Invite friends", robots: { index: false, follow: false } };

export default function Page() {
  return <InviteView />;
}
