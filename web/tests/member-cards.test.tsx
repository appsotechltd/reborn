import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CardView } from "@/components/CardView";
import { IllustratedVideo } from "@/components/IllustratedVideo";
import { PostActions } from "@/components/PostActions";
import { AuthProvider } from "@/lib/auth";
import { reasonText } from "@/lib/social";
import {
  audioUnits,
  kenBurns,
  looksLikeMemberCard,
  monthlyBuys,
  sceneAt,
  sceneOpacities,
  sceneProgress,
  spokenWords,
  videoDuration,
  videoUnits,
  visibilityLabel,
} from "@/lib/studio";
import type { CardVideo } from "@/lib/types";
import { makeCard, makePost } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/ideas/my-walk-k3x9p--01",
}));

const words = (n: number) => Array.from({ length: n }, () => "word").join(" ");
const author = { id: "w1", handle: "grace", display_name: "Grace" };
const memberCard = (over = {}) =>
  makeCard({ id: "my-walk-k3x9p--01", author, apply_it: "", locator: null, credit: "Written by Grace on Reborn", ...over });

describe("studio prices", () => {
  it("counts the words the narration reads, as the server does", () => {
    // "Title." + body, then "Apply it." and the tip.
    expect(spokenWords({ title: "Two words", body: words(10), apply_it: "" })).toBe(12);
    expect(spokenWords({ title: "Two words", body: words(10), apply_it: "do it" })).toBe(16);
  });

  it("charges 1 unit per started 50 words, at least 1", () => {
    expect(audioUnits({ title: "", body: "", apply_it: "" })).toBe(1);
    expect(audioUnits({ title: "a", body: words(49), apply_it: "" })).toBe(1);
    expect(audioUnits({ title: "a", body: words(50), apply_it: "" })).toBe(2);
    expect(audioUnits({ title: "a", body: words(149), apply_it: "" })).toBe(3);
  });

  it("prices a video as planning + 4 illustrations + the audio", () => {
    expect(videoUnits({ title: "a", body: words(149), apply_it: "" })).toBe(1 + 16 + 3);
    const rates = [{ kind: "illustration", units: 5, per: "" }];
    expect(videoUnits({ title: "a", body: "b", apply_it: "" }, 2, rates)).toBe(1 + 10 + 1);
  });

  it("says what a month of units buys", () => {
    const rates = [
      { kind: "illustration", units: 4, per: "" },
      { kind: "audio", units: 3, per: "" },
      { kind: "video", units: 20, per: "" },
    ];
    expect(monthlyBuys(250, rates)).toBe("about 12 videos, 62 illustrations or 83 one-minute audios");
  });

  it("labels audiences and hidden cards", () => {
    expect(visibilityLabel("private")).toBe("Only me");
    expect(visibilityLabel("subscribers")).toBe("Subscribers");
    expect(visibilityLabel("hidden")).toBe("Hidden");
    expect(visibilityLabel(undefined)).toBe("Everyone");
  });

  it("recognises member card ids", () => {
    expect(looksLikeMemberCard("my-morning-walk-k3x9p--01")).toBe(true);
    expect(looksLikeMemberCard("meditations-marcus-aurelius--01")).toBe(false);
  });
});

describe("illustrated video timing", () => {
  it("gives each scene an equal share", () => {
    expect(sceneAt(0, 40, 4)).toBe(0);
    expect(sceneAt(9.9, 40, 4)).toBe(0);
    expect(sceneAt(10, 40, 4)).toBe(1);
    expect(sceneAt(39.9, 40, 4)).toBe(3);
    expect(sceneAt(50, 40, 4)).toBe(3);
  });

  it("cross-fades each scene in over 0.8 s before its turn", () => {
    expect(sceneOpacities(0, 40, 4)).toEqual([1, 0, 0, 0]);
    expect(sceneOpacities(9.2, 40, 4)[1]).toBeCloseTo(0);
    expect(sceneOpacities(9.6, 40, 4)[1]).toBeCloseTo(0.5);
    expect(sceneOpacities(10, 40, 4)).toEqual([1, 1, 0, 0]);
    expect(sceneOpacities(40, 40, 4)).toEqual([1, 1, 1, 1]);
  });

  it("drifts each scene from start to end of its time on screen", () => {
    expect(sceneProgress(1, 9.2, 40, 4)).toBe(0);
    expect(sceneProgress(1, 20, 40, 4)).toBe(1);
    expect(sceneProgress(0, 5, 40, 4)).toBeCloseTo(0.5);
    const a = kenBurns(0, 0);
    const b = kenBurns(0, 1);
    expect(b.scale).toBeGreaterThan(a.scale);
    expect(kenBurns(1, 1).scale).toBeLessThan(kenBurns(1, 0).scale);
  });

  it("times scenes by the real audio once known", () => {
    expect(videoDuration(null, 42)).toBe(42);
    expect(videoDuration(Number.NaN, 42)).toBe(42);
    expect(videoDuration(44.5, 42)).toBe(44.5);
  });
});

describe("member cards on the page", () => {
  afterEach(() => {
    window.localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("credits the member, linked to their page, instead of a book", () => {
    render(<CardView card={memberCard()} />);
    const byline = screen.getByTestId("card-byline");
    expect(byline.textContent).toBe("by Grace");
    expect(screen.getByRole("link", { name: "Grace" }).getAttribute("href")).toBe("/u/grace");
    // An empty Apply it is left out.
    expect(screen.queryByRole("region", { name: "Apply it" })).toBeNull();
  });

  it("reads a writer reason", () => {
    expect(reasonText({ kind: "writer", label: "Grace" })).toBe("From Grace, who you follow");
  });

  it("shows the illustrated video, with no captions, and plays its narration", () => {
    const video: CardVideo = {
      kind: "illustrated",
      scenes: [1, 2, 3, 4].map((n) => ({ url: `https://media.example/s${n}.webp`, width: 1024, height: 1536 })),
      audio_url: "https://media.example/a.mp3",
      voice: "af_heart",
      duration_s: 40,
    };
    const play = vi.fn(() => Promise.resolve());
    const { container } = render(<IllustratedVideo video={video} title="My walk" />);
    const audio = container.querySelector("audio") as HTMLAudioElement;
    audio.play = play;
    expect(container.querySelectorAll("img[data-scene]")).toHaveLength(4);
    expect(container.querySelector("track")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: /illustrated video: My walk/ }));
    expect(play).toHaveBeenCalled();
  });

  it("puts the illustrated video on full screen, or fills the window where the browser can't", () => {
    const video: CardVideo = {
      kind: "illustrated",
      scenes: [1, 2].map((n) => ({ url: `https://media.example/s${n}.webp`, width: 1024, height: 1536 })),
      audio_url: "https://media.example/a.mp3",
      voice: "af_heart",
      duration_s: 40,
    };
    const { container } = render(<IllustratedVideo video={video} title="My walk" />);
    const audio = container.querySelector("audio") as HTMLAudioElement;
    audio.play = vi.fn(() => Promise.resolve());
    fireEvent.click(screen.getByRole("button", { name: /illustrated video: My walk/ }));
    const frame = container.querySelector("[data-testid=illustrated-video] > div") as HTMLElement;

    // No full-screen API (an iPhone): the frame fills the window, and Esc leaves.
    fireEvent.click(screen.getByRole("button", { name: "Full screen" }));
    expect(frame.dataset.fullscreen).toBe("window");
    expect(container.querySelector("img[data-scene]")?.className).toContain("object-contain");
    fireEvent.keyDown(window, { key: "Escape" });
    expect(frame.dataset.fullscreen).toBeUndefined();

    const request = vi.fn(() => Promise.resolve());
    frame.requestFullscreen = request;
    fireEvent.click(screen.getByRole("button", { name: "Full screen" }));
    expect(request).toHaveBeenCalled();
    expect(frame.dataset.fullscreen).toBe("real");
    expect(screen.getByRole("button", { name: "Exit full screen" })).toBeTruthy();
  });

  describe("actions", () => {
    beforeEach(() => {
      const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
      window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
      vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response(null, { status: 204 }))));
    });

    it("lets readers report someone else's card and tells the gift goes to them", async () => {
      render(
        <AuthProvider>
          <PostActions post={makePost({ card: memberCard() })} />
        </AuthProvider>,
      );
      fireEvent.click(screen.getByRole("button", { name: "Report this card" }));
      fireEvent.click(screen.getByRole("button", { name: "Report" }));
      await waitFor(() => expect(screen.getByText("Thanks, we'll take a look")).toBeTruthy());
      const call = vi.mocked(fetch).mock.calls.find(([u]) => String(u).endsWith("/v1/posts/my-walk-k3x9p--01/report"));
      expect(call?.[1]?.method).toBe("POST");
    });

    it("has no report on library cards and no gift on your own", () => {
      const { unmount } = render(
        <AuthProvider>
          <PostActions post={makePost()} />
        </AuthProvider>,
      );
      expect(screen.queryByRole("button", { name: "Report this card" })).toBeNull();
      unmount();
      render(
        <AuthProvider>
          <PostActions post={makePost({ card: memberCard({ author: { id: "u1", handle: "ada", display_name: "Ada" } }) })} />
        </AuthProvider>,
      );
      expect(screen.queryByRole("button", { name: /gift/i })).toBeNull();
      expect(screen.queryByRole("button", { name: "Report this card" })).toBeNull();
    });
  });
});
