import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getCircle, loadOr } from "@/lib/server-api";
import { CircleView } from "./CircleView";

export const metadata: Metadata = { title: "Book circle", robots: { index: false, follow: true } };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  // An unknown circle is a real 404. Its members, messages and the viewer's role load in the browser.
  const { data: circle, ok } = await loadOr(() => getCircle(id), null);
  if (ok && !circle) notFound();
  return <CircleView id={id} />;
}
