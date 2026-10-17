import { describe, expect, it } from "vitest";
import { cardPreviewMedia, coverPreviewMedia } from "@/lib/preview-media";
import type { Card } from "@/lib/types";

const base = { id: "a--01", title: "An idea" } as Card;
const explainer = {
  kind: "animated",
  video_url: "v.mp4",
  poster_url: "https://m/v.jpg",
  duration_s: 50,
  width: 720,
  height: 1280,
  narrated: true,
};

describe("link preview media", () => {
  it("prefers the wide video poster, then the card picture, then the image post, then the tall poster", () => {
    const image = { url: "https://m/c.webp", type: "illustration", caption: "" };
    const post_image = { url: "https://m/p.jpg", width: 1080, height: 1350, alt: "" };
    const landscape = { video_url: "w.mp4", poster_url: "https://m/w.jpg", width: 1280, height: 720 };
    expect(cardPreviewMedia({ ...base, image, post_image, explainer: { ...explainer, landscape } })?.url).toBe("https://m/w.jpg");
    expect(cardPreviewMedia({ ...base, image, post_image, explainer })?.url).toBe("https://m/c.webp");
    expect(cardPreviewMedia({ ...base, post_image, explainer })).toEqual({ url: "https://m/p.jpg", width: 1080, height: 1350 });
    expect(cardPreviewMedia({ ...base, explainer })?.url).toBe("https://m/v.jpg");
  });

  it("keeps the drawn text preview for text-only content", () => {
    expect(cardPreviewMedia(base)).toBeNull();
    expect(coverPreviewMedia(null)).toBeNull();
    expect(coverPreviewMedia({ url: "https://m/g.webp", type: "illustration", caption: "" })).toEqual({ url: "https://m/g.webp" });
  });
});
