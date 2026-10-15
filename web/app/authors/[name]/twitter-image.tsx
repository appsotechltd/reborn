import { authorImage, OG_ALT } from "@/lib/og-image";
import { authorFromParam } from "@/lib/social";

export const revalidate = 600;
export const alt = OG_ALT;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ name: string }> }) {
  const { name } = await params;
  return authorImage(authorFromParam(name));
}
