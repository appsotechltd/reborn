import sharp from "sharp";
import { mediaUrl } from "./config";
import type { PreviewMedia } from "./preview-media";

const W = 1200;
const H = 630;

/**
 * Fetches [media] and fits it to a 1200x630 JPEG (small enough for WhatsApp). Pictures close to
 * the preview's shape are cropped to fill it; tall or square ones (image posts, tall posters)
 * sit whole over a dimmed, blurred copy of themselves so their words are not cut off.
 * Null when the picture can't be fetched or read, so the caller falls back to the text preview.
 */
export async function mediaPreviewImage(media: PreviewMedia): Promise<Response | null> {
  try {
    // R2 sends no CORS headers, which only matters in browsers; this runs on the server.
    const res = await fetch(mediaUrl(media.url), { signal: AbortSignal.timeout(8000), cache: "no-store" });
    if (!res.ok) return null;
    const input = Buffer.from(await res.arrayBuffer());
    const meta = await sharp(input).metadata();
    const ratio = (meta.width ?? W) / (meta.height ?? H);
    let out: Buffer;
    if (ratio >= 1.3) {
      out = await sharp(input).resize(W, H, { fit: "cover", position: "attention" }).jpeg({ quality: 82, mozjpeg: true }).toBuffer();
    } else {
      const backdrop = await sharp(input).resize(W, H, { fit: "cover" }).blur(36).modulate({ brightness: 0.55 }).toBuffer();
      const front = await sharp(input).resize(W, H, { fit: "inside" }).toBuffer();
      out = await sharp(backdrop)
        .composite([{ input: front, gravity: "centre" }])
        .jpeg({ quality: 82, mozjpeg: true })
        .toBuffer();
    }
    return new Response(new Uint8Array(out), {
      headers: { "content-type": "image/jpeg", "cache-control": "public, max-age=3600, s-maxage=86400" },
    });
  } catch {
    return null;
  }
}

/** Re-encodes a drawn (PNG) preview as JPEG, so every preview of a route has one type. */
export async function asJpeg(image: Response): Promise<Response> {
  const png = Buffer.from(await image.arrayBuffer());
  const out = await sharp(png).jpeg({ quality: 90 }).toBuffer();
  return new Response(new Uint8Array(out), {
    headers: { "content-type": "image/jpeg", "cache-control": image.headers.get("cache-control") ?? "public, max-age=600" },
  });
}
