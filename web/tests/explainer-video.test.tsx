import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { CardView } from "@/components/CardView";
import { makeCard } from "./fixtures";

const explainer = {
  kind: "animated",
  video_url: "/media/explainers/example-book--01.mp4",
  poster_url: "/media/explainers/example-book--01.jpg",
  captions_url: "/media/explainers/example-book--01.vtt",
  duration_s: 52.4,
  width: 720,
  height: 1280,
  narrated: false,
};

describe("explainer video", () => {
  it("plays the card's explainer from the API, with captions, and keeps the credit", () => {
    const { container } = render(<CardView card={makeCard({ explainer })} />);
    const video = screen.getByLabelText(/animated explainer: small steps beat big plans/i) as HTMLVideoElement;
    expect(video.getAttribute("preload")).toBe("none");
    expect(video.getAttribute("poster")).toMatch(/^https?:\/\/[^/]+\/media\/explainers\/example-book--01\.jpg$/);
    expect(container.querySelector("video")?.getAttribute("src")).toMatch(/\/media\/explainers\/example-book--01\.mp4$/);
    expect(container.querySelector("track")?.getAttribute("kind")).toBe("captions");
    expect(screen.getByText(/52 s/)).toBeTruthy();
    expect(screen.queryByText(/captions on screen/)).toBeNull();
    expect(container.querySelector("track")?.hasAttribute("default")).toBe(false);
  });

  it("keeps absolute URLs (CDN) as they are", () => {
    const { container } = render(
      <CardView card={makeCard({ explainer: { ...explainer, video_url: "https://cdn.example.org/x.mp4", narrated: true } })} />,
    );
    expect(container.querySelector("video")?.getAttribute("src")).toBe("https://cdn.example.org/x.mp4");
    expect(screen.queryByText(/captions on screen/)).toBeNull();
  });

  it("renders nothing for cards without a video", () => {
    render(<CardView card={makeCard()} />);
    expect(screen.queryByTestId("explainer")).toBeNull();
  });
});
