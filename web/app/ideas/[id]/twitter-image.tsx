import { ideaImage } from "@/lib/og-image";

export const revalidate = 600;
export const alt = "Idea card from Reborn";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return ideaImage(id);
}
