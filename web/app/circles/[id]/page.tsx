import type { Metadata } from "next";
import { CircleView } from "./CircleView";

export const metadata: Metadata = { title: "Book circle", robots: { index: false, follow: true } };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <CircleView id={id} />;
}
