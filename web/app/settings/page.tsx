import type { Metadata } from "next";
import { SettingsView } from "./SettingsView";

export const metadata: Metadata = { title: "Settings", robots: { index: false, follow: false } };

export default function Page() {
  return <SettingsView />;
}
