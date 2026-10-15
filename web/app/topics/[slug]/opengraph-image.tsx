import { topicImage, OG_ALT } from "@/lib/og-image";

export const revalidate = 600;
export const alt = OG_ALT;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return topicImage(slug);
}
