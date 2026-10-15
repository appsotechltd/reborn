import { act, fireEvent, render, screen, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ListenButton, ListenIconButton } from "@/components/ListenButton";
import { CardsBrowser } from "@/components/CardsBrowser";
import { ListenDock } from "@/components/ListenDock";
import { Timeline } from "@/components/Timeline";
import { AuthProvider } from "@/lib/auth";
import { ListenProvider } from "@/lib/listen";
import { isListeningPlaying, setListeningPlaying, videoStarted } from "@/lib/media-focus";
import { makeCard, makePost } from "./fixtures";

const router = vi.hoisted(() => ({ push: vi.fn(), replace: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => router,
  usePathname: () => "/",
}));

const voiced = (n: number) =>
  makeCard({
    id: `example-book--0${n}`,
    title: `Idea ${n}`,
    audio: { url: `/audio/example-book--0${n}.mp3`, duration_s: 40, voice: "bm_george", voice_name: "George" },
  });

function App({ children }: { children: ReactNode }) {
  return (
    <AuthProvider>
      <ListenProvider>
        {children}
        <ListenDock />
      </ListenProvider>
    </AuthProvider>
  );
}

describe("Listen mode on the web", () => {
  beforeEach(() => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
    // jsdom doesn't scroll.
    Element.prototype.scrollIntoView = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ posts: [], next_cursor: null }))));
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    setListeningPlaying(false);
  });

  it("plays a card from its page, with the mini-player and the full player", () => {
    render(
      <App>
        <ListenButton card={voiced(1)} />
      </App>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Listen" }));
    expect(HTMLMediaElement.prototype.play).toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Pause", pressed: true })).toBeTruthy();

    const bar = screen.getByRole("region", { name: "Listen mode" });
    expect(within(bar).getByText("Idea 1")).toBeTruthy();
    expect(within(bar).getByText("An Example Book · Ada Example")).toBeTruthy();
    // One card from its page: no queue to move through.
    expect((within(bar).getByRole("button", { name: "Next idea" }) as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(within(bar).getByRole("button", { name: /Idea 1.*Open the player/ }));
    const sheet = screen.getByRole("dialog", { name: "Idea 1" });
    expect(within(sheet).getByText("Voice: George")).toBeTruthy();
    expect(within(sheet).getByRole("link", { name: "Open card" }).getAttribute("href")).toBe("/ideas/example-book--01");
    const slider = within(sheet).getByRole("slider", { name: "Position in this idea" });
    expect(slider.getAttribute("aria-valuetext")).toBe("0:00 of 0:40");
    fireEvent.click(within(sheet).getByRole("button", { name: "1.5×" }));
    expect(within(sheet).getByRole("button", { name: "1.5×" }).getAttribute("aria-pressed")).toBe("true");
    expect(window.localStorage.getItem("reborn.listen.speed")).toBe("1.5");
    fireEvent.change(within(sheet).getByLabelText(/Sleep timer/), { target: { value: "card" } });
    expect((within(sheet).getByLabelText(/Sleep timer/) as HTMLSelectElement).value).toBe("card");

    fireEvent.click(within(sheet).getByRole("button", { name: "Stop listening" }));
    expect(screen.queryByRole("region", { name: "Listen mode" })).toBeNull();
    expect(screen.getByRole("button", { name: "Listen" })).toBeTruthy();
  });

  it("opens the card the audio moves on to", () => {
    router.push.mockClear();
    router.replace.mockClear();
    render(
      <App>
        <CardsBrowser cards={[voiced(1), voiced(2)]} queue="source:example-book" listenLabel="Listen to this book" context="from this book" />
        <ListenButton card={voiced(1)} />
      </App>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Listen to this book" }));
    // Starting opens nothing.
    expect(router.push).not.toHaveBeenCalled();
    expect(router.replace).not.toHaveBeenCalled();
    const bar = screen.getByRole("region", { name: "Listen mode" });
    fireEvent.click(within(bar).getByRole("button", { name: "Next idea" }));
    // The book's page opens the card; a card's page swaps itself for it.
    expect(router.push).toHaveBeenCalledWith("/ideas/example-book--02");
    expect(router.replace).toHaveBeenCalledWith("/ideas/example-book--02");
  });

  it("hides the card's Listen button when nothing here can read it", () => {
    // jsdom has no speechSynthesis, and this card has no recording.
    render(
      <App>
        <ListenButton card={makeCard()} />
      </App>,
    );
    expect(screen.queryByRole("button", { name: "Listen" })).toBeNull();
  });

  it("takes turns with videos", () => {
    render(
      <App>
        <ListenButton card={voiced(1)} />
      </App>,
    );
    const video = document.createElement("video");
    document.body.append(video);
    Object.defineProperty(video, "paused", { configurable: true, get: () => false });
    const pause = vi.spyOn(video, "pause");
    fireEvent.click(screen.getByRole("button", { name: "Listen" }));
    expect(isListeningPlaying()).toBe(true);
    expect(pause).toHaveBeenCalled();
    act(() => videoStarted());
    expect(isListeningPlaying()).toBe(false);
    expect(screen.getByRole("button", { name: "Resume" })).toBeTruthy();
    video.remove();
  });

  it("starts Listen mode from the feed", () => {
    const posts = [makePost({ card: voiced(1) }), makePost({ card: voiced(2) })];
    render(
      <App>
        <Timeline initialPosts={posts} initialCursor={null} topics={[{ slug: "health", name: "Health" }]} />
      </App>,
    );
    // The wider screens' button above the feed (phones have it in the header).
    const buttons = screen.getAllByRole("button", { name: "Listen to this feed" });
    expect(buttons).toHaveLength(1);
    fireEvent.click(buttons[0]);
    const bar = screen.getByRole("region", { name: "Listen mode" });
    expect(within(bar).getByText("Idea 1")).toBeTruthy();
    fireEvent.click(within(bar).getByRole("button", { name: "Next idea" }));
    expect(within(bar).getByText("Idea 2")).toBeTruthy();
    // The feed scrolls to the post now playing.
    const list = screen.getByRole("list", { name: "Timeline" });
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledTimes(1);
    expect(vi.mocked(Element.prototype.scrollIntoView).mock.contexts[0]).toBe(list.children[1]);
  });

  it("plays one feed post's card from its Listen button, and pauses it", () => {
    render(
      <App>
        <ListenIconButton card={voiced(2)} />
      </App>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Listen to this idea" }));
    expect(within(screen.getByRole("region", { name: "Listen mode" })).getByText("Idea 2")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Pause this idea", pressed: true }));
    expect(screen.getByRole("button", { name: "Resume this idea", pressed: false })).toBeTruthy();
  });

  it("turns background music on and off from the player", () => {
    render(
      <App>
        <ListenButton card={voiced(1)} />
      </App>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Listen" }));
    const bar = screen.getByRole("region", { name: "Listen mode" });
    fireEvent.click(within(bar).getByRole("button", { name: /Idea 1.*Open the player/ }));
    const sheet = screen.getByRole("dialog", { name: "Idea 1" });
    const music = within(sheet).getByRole("switch", { name: /Background music/ });
    expect(music.getAttribute("aria-checked")).toBe("false");
    fireEvent.click(music);
    expect(within(sheet).getByRole("switch", { name: /Background music/ }).getAttribute("aria-checked")).toBe("true");
    expect(window.localStorage.getItem("reborn.listen.music")).toBe("1");
    fireEvent.click(music);
    expect(window.localStorage.getItem("reborn.listen.music")).toBe("0");
  });
});
