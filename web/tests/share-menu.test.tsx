import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ShareMenu } from "@/components/ShareMenu";
import { AuthProvider } from "@/lib/auth";
import { SiteUrlProvider } from "@/lib/site-url";

function renderMenu(props: Parameters<typeof ShareMenu>[0]) {
  render(
    <SiteUrlProvider url="https://iamreborn.app">
      <AuthProvider>
        <ShareMenu {...props} />
      </AuthProvider>
    </SiteUrlProvider>,
  );
  fireEvent.click(screen.getByRole("button", { name: /share/i }));
}

describe("<ShareMenu> for pages that aren't ideas", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("shares the page link to every network and never counts it as an idea share", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    renderMenu({ path: "/sources/meditations", title: "Meditations by Marcus Aurelius", what: "book", label: true });

    expect(screen.getByRole("heading", { name: "Share this book" })).toBeTruthy();
    const url = "https://iamreborn.app/sources/meditations";
    expect((screen.getByLabelText("Link to this book") as HTMLInputElement).value).toBe(url);
    const whatsapp = screen.getByRole("link", { name: /WhatsApp/ });
    expect(whatsapp.getAttribute("href")).toContain(encodeURIComponent(url));
    for (const name of [/Facebook/, /^X/, /LinkedIn/, /Telegram/, /Email/]) {
      expect(screen.getByRole("link", { name })).toBeTruthy();
    }
    fireEvent.click(whatsapp);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("<ShareMenu> for an idea with a video", () => {
  const explainer = {
    kind: "animated",
    video_url: "https://media.example.com/explainers/a--01.mp4",
    poster_url: "https://media.example.com/explainers/a--01.jpg",
    duration_s: 50,
    width: 720,
    height: 1280,
    narrated: true,
    landscape: {
      video_url: "https://media.example.com/explainers/a--01-wide.mp4",
      poster_url: "https://media.example.com/explainers/a--01-wide.jpg",
      width: 1280,
      height: 720,
    },
  };
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    delete (navigator as Partial<Navigator>).share;
    delete (navigator as Partial<Navigator>).canShare;
  });

  it("offers the tall and wide video, and downloads it where there's no share sheet", () => {
    const clicked: string[] = [];
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
      clicked.push(this.href);
    });
    renderMenu({ postId: "a--01", title: "An idea", video: { cardId: "a--01", explainer } });
    const tall = screen.getByRole("button", { name: /Tall video.*Status, Reels, Shorts, TikTok/ });
    const wide = screen.getByRole("button", { name: /Wide video.*YouTube, Facebook, X, LinkedIn/ });
    fireEvent.click(wide);
    fireEvent.click(tall);
    expect(clicked).toEqual([
      expect.stringMatching(/\/v1\/cards\/a--01\/video\?shape=wide$/),
      expect.stringMatching(/\/v1\/cards\/a--01\/video\?shape=tall$/),
    ]);
  });

  it("only offers the tall video before the wide cut exists", () => {
    renderMenu({ postId: "a--01", title: "An idea", video: { cardId: "a--01", explainer: { ...explainer, landscape: null } } });
    expect(screen.getByRole("button", { name: /Tall video/ })).toBeTruthy();
    expect(screen.queryByRole("button", { name: /Wide video/ })).toBeNull();
  });

  it("puts the video file in the phone's share sheet", async () => {
    const share = vi.fn(() => Promise.resolve());
    Object.assign(navigator, { share, canShare: () => true });
    const fetchMock = vi.fn((url: string) =>
      Promise.resolve(url.includes("/video?") ? new Response("mp4", { headers: { "Content-Type": "video/mp4" } }) : new Response(null, { status: 204 })),
    );
    vi.stubGlobal("fetch", fetchMock);
    renderMenu({ postId: "a--01", title: "An idea", video: { cardId: "a--01", explainer } });
    fireEvent.click(screen.getByRole("button", { name: /Tall video/ }));
    await waitFor(() => expect(share).toHaveBeenCalled());
    expect(String(fetchMock.mock.calls[0][0])).toMatch(/\/v1\/cards\/a--01\/video\?shape=tall$/);
    const arg = (share.mock.calls[0] as unknown as [ShareData])[0];
    expect(arg.files?.[0].name).toBe("reborn-a--01-tall.mp4");
    expect(arg.files?.[0].type).toBe("video/mp4");
  });
});
