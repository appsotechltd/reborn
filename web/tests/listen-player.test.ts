import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  CHIME_URL,
  heardOutcome,
  listenText,
  ListenPlayer,
  previousAction,
  shouldLoadMore,
  sourceLine,
  type ListenDeps,
  type ListenItem,
} from "@/lib/listen-player";
import type { PostsResponse } from "@/lib/types";
import { makeCard, makePost } from "./fixtures";

class FakeAudio extends EventTarget {
  private url = "";
  // Like a real element, a new source starts from the beginning.
  get src() {
    return this.url;
  }
  set src(v: string) {
    this.url = v;
    this.currentTime = 0;
  }
  preload = "";
  muted = false;
  currentTime = 0;
  duration = NaN;
  playbackRate = 1;
  defaultPlaybackRate = 1;
  paused = true;
  ended = false;
  playResult: () => Promise<void> = () => Promise.resolve();
  play = vi.fn(() => {
    this.paused = false;
    return this.playResult();
  });
  pause = vi.fn(() => {
    this.paused = true;
  });
  removeAttribute(name: string) {
    if (name === "src") this.url = "";
  }
  fire(type: string) {
    this.dispatchEvent(new Event(type));
  }
}

class FakeUtterance {
  lang = "";
  rate = 1;
  onend: (() => void) | null = null;
  onerror: ((e: { error: string }) => void) | null = null;
  constructor(public text: string) {}
}

function withAudio(n: number, extra: Partial<Parameters<typeof makeCard>[0]> = {}) {
  const id = `example-book--${String(n).padStart(2, "0")}`;
  return makeCard({
    id,
    title: `Idea ${n}`,
    audio: { url: `/audio/${id}.mp3`, duration_s: 40, voice: "bm_george", voice_name: "George" },
    ...extra,
  });
}

function items(...cards: ReturnType<typeof makeCard>[]): ListenItem[] {
  return cards.map((card) => ({ id: card.id, card }));
}

function setup(opts: { signedIn?: boolean; speech?: boolean; mediaSession?: boolean; timeline?: ListenDeps["api"]["timeline"] } = {}) {
  const audios: FakeAudio[] = [];
  const spoken: FakeUtterance[] = [];
  const synth = { speaking: false, pending: false, speak: vi.fn((u: FakeUtterance) => spoken.push(u)), cancel: vi.fn() };
  const handlers = new Map<string, ((d: MediaSessionActionDetails) => void) | null>();
  const mediaSession = {
    metadata: null as unknown,
    playbackState: "none",
    setActionHandler: vi.fn((a: string, h: ((d: MediaSessionActionDetails) => void) | null) => handlers.set(a, h)),
    setPositionState: vi.fn(),
  };
  const api = {
    timeline: opts.timeline ?? vi.fn(async (): Promise<PostsResponse> => ({ posts: [], next_cursor: null })),
    markSeen: vi.fn().mockResolvedValue(undefined),
    recordView: vi.fn().mockResolvedValue(undefined),
  };
  const player = new ListenPlayer({
    api: api as unknown as ListenDeps["api"],
    signedIn: () => opts.signedIn ?? true,
    createAudio: () => {
      const a = new FakeAudio();
      audios.push(a);
      return a as unknown as HTMLAudioElement;
    },
    speech: () => (opts.speech === false ? null : (synth as unknown as SpeechSynthesis)),
    createUtterance: (text) => new FakeUtterance(text) as unknown as SpeechSynthesisUtterance,
    mediaSession: () => (opts.mediaSession ? (mediaSession as unknown as MediaSession) : null),
  });
  // The main element is the first one created (preloading elements come after it).
  const main = () => audios.find((a) => a.preload === "auto" && !a.muted)!;
  return { player, api, audios, main, spoken, synth, handlers, mediaSession };
}

/** Plays the current recording on to `to` seconds, a quarter second at a time. */
function playTo(a: FakeAudio, to: number) {
  while (a.currentTime < to) {
    a.currentTime = Math.min(to, a.currentTime + 0.25);
    a.fire("timeupdate");
  }
}

function end(a: FakeAudio) {
  a.ended = true;
  a.fire("ended");
  a.ended = false;
  a.currentTime = 0;
}

beforeEach(() => {
  try {
    window.localStorage.clear();
  } catch {
    // ignore
  }
});
afterEach(() => {
  vi.useRealTimers();
});

describe("Listen mode rules", () => {
  it("restarts the current card after 3 s, else goes to the previous one", () => {
    expect(previousAction(3.5, 2)).toBe("restart");
    expect(previousAction(2.9, 2)).toBe("previous");
    expect(previousAction(1, 0)).toBe("restart");
  });

  it("counts 70% or the end as read, after 5 s as seen, and earlier skips as nothing", () => {
    expect(heardOutcome(28, 40, false)).toBe("read");
    expect(heardOutcome(2, 40, true)).toBe("read");
    expect(heardOutcome(27, 40, false)).toBe("seen");
    expect(heardOutcome(5, 40, false)).toBe("seen");
    expect(heardOutcome(4.9, 40, false)).toBe("none");
  });

  it("loads the next page when 3 or fewer cards are left", () => {
    expect(shouldLoadMore(10, 5, true)).toBe(false);
    expect(shouldLoadMore(10, 6, true)).toBe(true);
    expect(shouldLoadMore(10, 9, false)).toBe(false);
  });

  it("reads the same script as the recordings", () => {
    const card = makeCard({ disclaimer: "Talk to a doctor first." });
    const text = listenText(card);
    expect(text.startsWith("Small steps beat big plans\n\nA first paragraph")).toBe(true);
    expect(text).toContain("Apply it. Pick one tiny step");
    expect(text).toContain("Talk to a doctor first.");
    expect(text.endsWith("From An Example Book, by Ada Example.")).toBe(true);
    expect(sourceLine(card)).toBe("An Example Book · Ada Example");
  });
});

describe("ListenPlayer", () => {
  it("plays the queue in order, with the chime between cards", () => {
    const { player, main } = setup();
    player.start({ items: items(withAudio(1), withAudio(2)) });
    const a = main();
    expect(a.src).toBe("http://localhost:8080/audio/example-book--01.mp3");
    expect(a.play).toHaveBeenCalled();
    end(a);
    expect(player.getState().phase).toBe("chime");
    expect(a.src).toBe(CHIME_URL);
    expect(player.getState().index).toBe(1);
    end(a);
    expect(player.getState().phase).toBe("card");
    expect(a.src).toBe("http://localhost:8080/audio/example-book--02.mp3");
    end(a);
    expect(player.getState().phase).toBe("finished");
    expect(player.getState().playing).toBe(false);
  });

  it("goes next without the chime, and previous restarts after 3 s", () => {
    const { player, main } = setup();
    player.start({ items: items(withAudio(1), withAudio(2)) });
    const a = main();
    player.next();
    expect(player.getState().index).toBe(1);
    expect(a.src).toContain("example-book--02.mp3");
    playTo(a, 4);
    player.previous();
    expect(player.getState().index).toBe(1);
    expect(a.currentTime).toBe(0);
    playTo(a, 2);
    player.previous();
    expect(player.getState().index).toBe(0);
    expect(a.src).toContain("example-book--01.mp3");
  });

  it("marks nothing for an early skip, seen after 5 s, and seen and read at 70%", () => {
    const { player, api, main } = setup();
    player.start({ items: items(withAudio(1), withAudio(2), withAudio(3), withAudio(4)) });
    const a = main();
    playTo(a, 4);
    player.next();
    expect(api.markSeen).not.toHaveBeenCalled();
    playTo(a, 6);
    player.next();
    expect(api.markSeen).toHaveBeenCalledWith(["example-book--02"]);
    expect(api.recordView).not.toHaveBeenCalled();
    // Read as soon as 70% has been heard, without waiting for the end, and only once.
    playTo(a, 28);
    expect(api.markSeen).toHaveBeenLastCalledWith(["example-book--03"]);
    expect(api.recordView).toHaveBeenCalledWith("example-book--03");
    end(a);
    end(a); // the chime
    expect(api.recordView).toHaveBeenCalledTimes(1);
    // Scrubbing ahead isn't hearing it.
    player.seek(35);
    player.next();
    expect(api.recordView).toHaveBeenCalledTimes(1);
  });

  it("records nothing when signed out", () => {
    const { player, api, main } = setup({ signedIn: false });
    player.start({ items: items(withAudio(1), withAudio(2)) });
    playTo(main(), 40);
    end(main());
    expect(api.markSeen).not.toHaveBeenCalled();
    expect(api.recordView).not.toHaveBeenCalled();
  });

  it("loads the next timeline page when 3 or fewer remain, with the feed's topics", async () => {
    const more = [makePost({ card: withAudio(6) }), makePost({ card: withAudio(2) })];
    const timeline = vi.fn(async (): Promise<PostsResponse> => ({ posts: more, next_cursor: null }));
    const { player } = setup({ timeline });
    player.start({ items: items(withAudio(1), withAudio(2), withAudio(3), withAudio(4), withAudio(5)), cursor: "c1", topics: "health" });
    expect(timeline).not.toHaveBeenCalled();
    player.next();
    expect(timeline).toHaveBeenCalledWith({ cursor: "c1", limit: 20, topics: "health" }, true);
    await vi.waitFor(() => expect(player.getState().items).toHaveLength(6));
    expect(player.getState().items[5].id).toBe("example-book--06");
    player.next();
    expect(timeline).toHaveBeenCalledTimes(1);
  });

  it("waits for the next page at the end of the queue, then carries on", async () => {
    let resolve: (p: PostsResponse) => void = () => {};
    const timeline = vi.fn(() => new Promise<PostsResponse>((r) => (resolve = r)));
    const { player, main } = setup({ timeline });
    player.start({ items: items(withAudio(1)), cursor: "c1" });
    end(main());
    expect(player.getState().phase).toBe("waiting");
    resolve({ posts: [makePost({ card: withAudio(2) })], next_cursor: null });
    await vi.waitFor(() => expect(player.getState().phase).toBe("card"));
    expect(player.getState().index).toBe(1);
    expect(main().src).toContain("example-book--02.mp3");
  });

  it("prefetches the next cards' recordings", () => {
    const { player, audios } = setup();
    player.start({ items: items(withAudio(1), withAudio(2), withAudio(3), withAudio(4), withAudio(5)) });
    const warm = audios.filter((a) => a.muted).map((a) => a.src);
    expect(warm).toEqual([2, 3, 4].map((n) => `http://localhost:8080/audio/example-book--0${n}.mp3`));
  });

  it("reads cards without a recording with the device voice, then carries on", () => {
    const { player, spoken, main } = setup();
    player.start({ items: items(makeCard({ id: "example-book--01" }), withAudio(2)) });
    expect(player.getState().voice).toBe("device");
    expect(spoken[0].text).toBe("Small steps beat big plans");
    while (spoken.length && player.getState().index === 0) {
      const last = spoken[spoken.length - 1];
      const before = spoken.length;
      last.onend?.();
      if (spoken.length === before) break;
    }
    expect(spoken.map((u) => u.text).join(" ")).toContain("From An Example Book, by Ada Example.");
    expect(player.getState().index).toBe(1);
    expect(player.getState().phase).toBe("chime");
    end(main());
    expect(player.getState().voice).toBe("recording");
  });

  it("falls back to the device voice when a recording fails, and skips when there is no voice", () => {
    const one = setup();
    one.player.start({ items: items(withAudio(1), withAudio(2)) });
    one.main().fire("error");
    expect(one.player.getState().voice).toBe("device");
    expect(one.spoken[0].text).toBe("Idea 1");

    const two = setup({ speech: false });
    two.player.start({ items: items(makeCard({ id: "example-book--01" }), withAudio(2)) });
    expect(two.player.getState().index).toBe(1);
    expect(two.main().src).toContain("example-book--02.mp3");
  });

  it("wires the lock screen and headphone controls", () => {
    const { player, handlers, mediaSession, main } = setup({ mediaSession: true });
    player.start({ items: items(withAudio(1), withAudio(2)) });
    for (const action of ["play", "pause", "nexttrack", "previoustrack", "seekbackward", "seekforward", "seekto"]) {
      expect(typeof handlers.get(action)).toBe("function");
    }
    expect(mediaSession.metadata).toMatchObject({
      title: "Idea 1",
      artist: "An Example Book · Ada Example",
      artwork: [{ src: "/listen-artwork.png", sizes: "512x512", type: "image/png" }],
    });
    expect(mediaSession.playbackState).toBe("playing");
    handlers.get("pause")!({ action: "pause" });
    expect(player.getState().playing).toBe(false);
    expect(mediaSession.playbackState).toBe("paused");
    handlers.get("play")!({ action: "play" });
    expect(player.getState().playing).toBe(true);
    handlers.get("seekto")!({ action: "seekto", seekTime: 12 });
    expect(main().currentTime).toBe(12);
    handlers.get("seekbackward")!({ action: "seekbackward" });
    expect(main().currentTime).toBe(2);
    handlers.get("nexttrack")!({ action: "nexttrack" });
    expect(player.getState().index).toBe(1);
    expect(mediaSession.metadata).toMatchObject({ title: "Idea 2" });
    expect(mediaSession.setPositionState).toHaveBeenCalled();
    player.stop();
    expect(handlers.get("play")).toBeNull();
    expect(mediaSession.metadata).toBeNull();
  });

  it("remembers the speed", () => {
    const first = setup();
    first.player.start({ items: items(withAudio(1)) });
    first.player.setSpeed(1.25);
    expect(first.main().playbackRate).toBe(1.25);
    const second = setup();
    second.player.start({ items: items(withAudio(1)) });
    expect(second.player.getState().speed).toBe(1.25);
    expect(second.main().playbackRate).toBe(1.25);
  });

  it("sleeps at the end of this card, or after the minutes chosen", () => {
    vi.useFakeTimers();
    const { player, main } = setup();
    player.start({ items: items(withAudio(1), withAudio(2), withAudio(3)) });
    player.setSleep("card");
    end(main());
    expect(player.getState()).toMatchObject({ index: 1, playing: false, sleep: null, phase: "card" });
    player.play();
    player.setSleep(15);
    vi.advanceTimersByTime(15 * 60_000);
    expect(player.getState().playing).toBe(false);
    expect(player.getState().sleep).toBeNull();
  });

  it("follows pauses from outside, like headphones unplugged", () => {
    const { player, main } = setup();
    player.start({ items: items(withAudio(1)) });
    const a = main();
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 1000);
    a.fire("pause");
    expect(player.getState().playing).toBe(false);
    vi.restoreAllMocks();
  });
});

describe("ListenPlayer.playCards (a book's or an author's cards)", () => {
  it("plays a fixed list in order, never pages the timeline, and finishes after the last card", () => {
    const { player, api, main } = setup();
    player.playCards([withAudio(3), withAudio(1), withAudio(2)], { queue: "source:example-book|all" });
    const s = player.getState();
    expect(s.queue).toBe("source:example-book|all");
    expect(s.single).toBe(false);
    expect(s.items.map((i) => i.id)).toEqual(["example-book--03", "example-book--01", "example-book--02"]);
    const a = main();
    expect(a.src).toContain("example-book--03.mp3");
    for (let n = 0; n < 2; n++) {
      end(a); // the card
      end(a); // the chime
    }
    expect(a.src).toContain("example-book--02.mp3");
    end(a);
    expect(player.getState().phase).toBe("finished");
    expect(api.timeline).not.toHaveBeenCalled();
  });

  it("records seen and read as in the timeline", async () => {
    const { player, api, main } = setup();
    player.playCards([withAudio(1), withAudio(2)]);
    expect(player.getState().queue).toBeNull();
    end(main());
    await Promise.resolve();
    expect(api.markSeen).toHaveBeenCalledWith(["example-book--01"]);
    expect(api.recordView).toHaveBeenCalledWith("example-book--01");
  });
});
