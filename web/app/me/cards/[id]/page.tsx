import type { Metadata } from "next";
import { MyCardView } from "./MyCardView";

export const metadata: Metadata = { title: "My card", robots: { index: false, follow: false } };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <MyCardView id={id} />;
}
