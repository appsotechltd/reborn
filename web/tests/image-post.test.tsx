import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { isImagePost } from "@/components/ImagePost";
import { PostCard } from "@/components/PostCard";
import { AuthProvider } from "@/lib/auth";
import { hasImage } from "@/lib/media-filter";
import { makeCard, makePost } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
}));

const postImage = { url: "https://media.example.com/images/posts/v1/example-book--01.jpg", width: 1080, height: 1350, alt: "A candle on a desk" };

describe("image posts", () => {
  it("shows the designed picture in place of the card text, linking to the card", () => {
    const post = makePost({ card: makeCard({ id: "example-book--01", title: "Small steps beat big plans", post_image: postImage }) });
    for (const snap of [false, true]) {
      const { container, unmount } = render(
        <AuthProvider>
          <PostCard post={post} snap={snap} />
        </AuthProvider>,
      );
      const img = screen.getByRole("img", { name: "Small steps beat big plans. A candle on a desk" });
      expect(img.getAttribute("src")).toBe(postImage.url);
      expect(img.closest("a")!.getAttribute("href")).toBe(`/ideas/${post.id}`);
      expect(screen.getByRole("link", { name: "Read the idea: Small steps beat big plans" })).toBeTruthy();
      expect(container.querySelector("[data-post-cover]")).toBeNull();
      expect(screen.queryByTestId("card-byline")).toBeNull();
      unmount();
    }
  });

  it("leaves video cards as videos, and counts as a picture for the Images filter", () => {
    const video = makeCard({ post_image: postImage, explainer: { kind: "animated", video_url: "/v.mp4" } as never });
    expect(isImagePost(video)).toBe(false);
    expect(isImagePost(makeCard({ post_image: postImage }))).toBe(true);
    expect(hasImage(makeCard({ post_image: postImage }))).toBe(true);
    expect(hasImage(makeCard({}))).toBe(false);
  });
});
