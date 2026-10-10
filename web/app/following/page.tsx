import type { Metadata } from "next";
import { FollowingView } from "./FollowingView";

export const metadata: Metadata = { title: "Following", robots: { index: false, follow: false } };

export default function Page() {
  return <FollowingView />;
}
