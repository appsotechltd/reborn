import type { Metadata } from "next";
import { AdminView } from "./AdminView";

export const metadata: Metadata = { title: "Dashboard", robots: { index: false, follow: false } };

export default function Page() {
  return <AdminView />;
}
