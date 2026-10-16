import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CardView } from "@/components/CardView";
import { AUTOPLAY_RATIO, resetPlayback } from "@/components/ExplainerVideo";
import { onVideoStarted, setListeningPlaying } from "@/lib/media-focus";
import { installFakeIO, setVisible, stubMatchMedia } from "./fake-io";
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

const card = (n: number) => makeCard({ id: `example-book--0${n}`, title: `Idea ${n}`, explainer });

// jsdom has no media playback: track paused state ourselves and let tests decide whether play() is allowed.
let refuse: (v: HTMLMediaElement) => boolean = () => false;
const paused = new WeakMap<HTMLMediaElement, boolean>();
const play = vi.fn(function (this: HTMLMediaElement) {
  if (refuse(this)) return Promise.reject(new DOMException("autoplay refused", "NotAllowedError"));
  paused.set(this, false);
  this.dispatchEvent(new Event("play"));
  return Promise.resolve();
});
const pause = vi.fn(function (this: HTMLMediaElement) {
  if (paused.get(this) === false) {
    paused.set(this, true);
    this.dispatchEvent(new Event("pause"));
  }
});

const flush = () => act(async () => {});

describe("feed video autoplay", () => {
  beforeEach(() => {
    installFakeIO();
    stubMatchMedia({});
    resetPlayback();
    refuse = () => false;
    play.mockClear();
    pause.mockClear();
    vi.spyOn(HTMLMediaElement.prototype, "play").mockImplementation(play);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(pause);
    vi.spyOn(HTMLMediaElement.prototype, "paused", "get").mockImplementation(function (this: HTMLMediaElement) {
      return paused.get(this) ?? true;
    });
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  const videoOf = (n: number) => screen.getByLabelText(`Animated explainer: Idea ${n}`) as HTMLVideoElement;

  it("stays still while Listen mode plays, and pauses Listen mode when the reader turns the sound on", async () => {
    const started = vi.fn();
    const off = onVideoStarted(started);
    setListeningPlaying(true);
    render(<CardView card={card(1)} feed />);
    const v = videoOf(1);
    await act(async () => setVisible(v, 1));
    expect(play).not.toHaveBeenCalled();
    setListeningPlaying(false);
    await act(async () => setVisible(v, 0));
    await act(async () => setVisible(v, 1));
    expect(play).toHaveBeenCalledTimes(1);
    // Playing muted by itself doesn't interrupt; choosing the sound does.
    expect(started).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Unmute video" }));
    expect(started).toHaveBeenCalledTimes(1);
    // Listen mode starting again pauses it.
    setListeningPlaying(true);
    expect(pause).toHaveBeenCalled();
    setListeningPlaying(false);
    off();
  });

  it("plays muted once 60% is on screen and pauses when it scrolls away", async () => {
    render(<CardView card={card(1)} feed />);
    const v = videoOf(1);
    setVisible(v, AUTOPLAY_RATIO - 0.1);
    expect(play).not.toHaveBeenCalled();

    await act(async () => setVisible(v, AUTOPLAY_RATIO));
    expect(play).toHaveBeenCalledTimes(1);
    expect(v.muted).toBe(true);
    expect(screen.getByRole("button", { name: "Unmute video" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Pause video" })).toBeTruthy();
    // No captions on screen: the track exists but is never turned on.
    expect(v.querySelector("track")?.hasAttribute("default")).toBe(false);

    await act(async () => setVisible(v, 0.2));
    expect(pause).toHaveBeenCalledTimes(1);
    expect(v.paused).toBe(true);
  });

  it("toggles the sound from the button and by tapping the video", async () => {
    render(<CardView card={card(1)} feed />);
    const v = videoOf(1);
    await act(async () => setVisible(v, 1));
    fireEvent.click(screen.getByRole("button", { name: "Unmute video" }));
    expect(v.muted).toBe(false);
    expect(screen.getByRole("button", { name: "Mute video" })).toBeTruthy();
    fireEvent.click(v);
    expect(v.muted).toBe(true);
    expect(screen.getByRole("button", { name: "Unmute video" })).toBeTruthy();
  });

  it("plays only one video at a time", async () => {
    render(
      <>
        <CardView card={card(1)} feed />
        <CardView card={card(2)} feed />
      </>,
    );
    const a = videoOf(1);
    const b = videoOf(2);
    await act(async () => setVisible(a, 1));
    expect(a.paused).toBe(false);
    await act(async () => setVisible(b, 0.8));
    expect(b.paused).toBe(false);
    expect(a.paused).toBe(true);
  });

  it("keeps the Play button when autoplay is refused, and plays with sound on tap", async () => {
    refuse = (v) => v.muted; // refuses muted autoplay; a tap (user gesture) is allowed
    render(<CardView card={card(1)} feed />);
    const v = videoOf(1);
    await act(async () => setVisible(v, 1));
    await flush();
    expect(v.paused).toBe(true);
    const fallback = screen.getByRole("button", { name: /play\s*the animated explainer/i });
    refuse = () => false;
    await act(async () => fireEvent.click(fallback));
    expect(v.paused).toBe(false);
    expect(v.muted).toBe(false);
    expect(screen.queryByRole("button", { name: /play\s*the animated explainer/i })).toBeNull();
  });

  it("does not restart a video the reader paused until it has left the screen", async () => {
    render(<CardView card={card(1)} feed />);
    const v = videoOf(1);
    await act(async () => setVisible(v, 1));
    fireEvent.click(screen.getByRole("button", { name: "Pause video" }));
    expect(v.paused).toBe(true);
    await act(async () => setVisible(v, 0.9));
    expect(v.paused).toBe(true);
    await act(async () => setVisible(v, 0));
    await act(async () => setVisible(v, 1));
    expect(v.paused).toBe(false);
  });

  it("does not autoplay when the reader prefers reduced motion", async () => {
    stubMatchMedia({ "prefers-reduced-motion": true });
    render(<CardView card={card(1)} feed />);
    await act(async () => setVisible(videoOf(1), 1));
    expect(play).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: /play\s*the animated explainer/i })).toBeTruthy();
  });

  it("opens a feed video full screen with sound, and goes back to muted", async () => {
    let fsEl: Element | null = null;
    Object.defineProperty(document, "fullscreenElement", { configurable: true, get: () => fsEl });
    const request = vi.fn(function (this: Element) {
      fsEl = request.mock.contexts.at(-1) as Element;
      document.dispatchEvent(new Event("fullscreenchange"));
      return Promise.resolve();
    });
    HTMLElement.prototype.requestFullscreen = request;
    try {
      render(<CardView card={card(1)} feed />);
      const v = videoOf(1);
      await act(async () => setVisible(v, 1));
      expect(v.muted).toBe(true);
      await act(async () => fireEvent.click(screen.getByRole("button", { name: "Full screen" })));
      expect(request.mock.contexts[0]).toBe(v);
      expect(v.muted).toBe(false);
      expect(v.paused).toBe(false);
      expect(v.controls).toBe(true);
      // Leaving full screen (Esc, or the browser's own button).
      fsEl = null;
      await act(async () => document.dispatchEvent(new Event("fullscreenchange")));
      expect(v.muted).toBe(true);
      expect(v.controls).toBe(false);
      expect(v.paused).toBe(false);
    } finally {
      delete (HTMLElement.prototype as Partial<HTMLElement>).requestFullscreen;
      delete (document as Partial<Document> & { fullscreenElement?: unknown }).fullscreenElement;
    }
  });

  it("offers full screen on a card's page once the video plays, using an iPhone's own player", async () => {
    render(<CardView card={card(1)} />);
    const v = videoOf(1) as HTMLVideoElement & { webkitEnterFullscreen?: () => void };
    expect(screen.queryByRole("button", { name: "Full screen" })).toBeNull();
    await act(async () => fireEvent.click(screen.getByRole("button", { name: /play\s*the animated explainer/i })));
    const enter = vi.fn();
    v.webkitEnterFullscreen = enter;
    fireEvent.click(screen.getByRole("button", { name: "Full screen" }));
    expect(enter).toHaveBeenCalled();
  });

  it("plays the landscape cut, filling the card, on tablets and laptops; phones keep portrait", async () => {
    const landscape = {
      video_url: "/media/explainers/example-book--01-wide.mp4",
      poster_url: "/media/explainers/example-book--01-wide.jpg",
      width: 1280,
      height: 720,
    };
    const wideCard = makeCard({ id: "example-book--01", title: "Idea 1", explainer: { ...explainer, landscape } });
    const { unmount } = render(<CardView card={wideCard} feed />);
    expect(videoOf(1).getAttribute("src")).toContain("example-book--01.mp4");
    expect(screen.getByTestId("explainer").querySelector("[data-shape]")?.getAttribute("data-shape")).toBe("portrait");
    unmount();

    stubMatchMedia({ "min-width: 768px": true });
    render(<CardView card={wideCard} feed />);
    await flush();
    const v = videoOf(1);
    expect(v.getAttribute("src")).toContain("example-book--01-wide.mp4");
    expect(v.getAttribute("poster")).toContain("example-book--01-wide.jpg");
    const frame = screen.getByTestId("explainer").querySelector("[data-shape]") as HTMLElement;
    expect(frame.dataset.shape).toBe("landscape");
    expect(frame.className).not.toContain("max-w-[22rem]");
  });

  it("loads the file without a CORS request (the media bucket sends no CORS headers)", () => {
    render(<CardView card={card(1)} />);
    expect(videoOf(1).hasAttribute("crossorigin")).toBe(false);
  });

  it("never autoplays on a card's own page", async () => {
    render(<CardView card={card(1)} />);
    await act(async () => setVisible(videoOf(1), 1));
    expect(play).not.toHaveBeenCalled();
  });
});
