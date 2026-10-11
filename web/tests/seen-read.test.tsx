import { act, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ApiClient } from "@/lib/api";
import { READ_AFTER_MS, SEEN_AFTER_MS, SEEN_BATCH_MS, useSeenTracker } from "@/lib/use-seen";

type Callback = (entries: Partial<IntersectionObserverEntry>[]) => void;
let fire: Callback = () => {};

class FakeObserver {
  constructor(cb: Callback) {
    fire = cb;
  }
  observe() {}
  unobserve() {}
  disconnect() {}
}

function Post({ api }: { api: ApiClient }) {
  const track = useSeenTracker(api, true);
  return <div data-post-id="p1" ref={track} />;
}

const visible = (el: Element, on: boolean): Partial<IntersectionObserverEntry> => ({
  target: el,
  isIntersecting: on,
  intersectionRatio: on ? 1 : 0,
  intersectionRect: { height: on ? 400 : 0 } as DOMRectReadOnly,
  rootBounds: { height: 800 } as DOMRectReadOnly,
});

describe("useSeenTracker", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.stubGlobal("IntersectionObserver", FakeObserver);
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  function setup() {
    const api = { markSeen: vi.fn().mockResolvedValue(undefined), recordView: vi.fn().mockResolvedValue(undefined) };
    const { container } = render(<Post api={api as unknown as ApiClient} />);
    return { api, el: container.querySelector("[data-post-id]")! };
  }

  it("marks a post scrolled past as seen but not read", () => {
    const { api, el } = setup();
    act(() => fire([visible(el, true)]));
    act(() => vi.advanceTimersByTime(SEEN_AFTER_MS + SEEN_BATCH_MS));
    act(() => fire([visible(el, false)]));
    act(() => vi.advanceTimersByTime(READ_AFTER_MS));
    expect(api.markSeen).toHaveBeenCalledWith(["p1"]);
    expect(api.recordView).not.toHaveBeenCalled();
  });

  it("counts a post as read once it stays on screen", () => {
    const { api, el } = setup();
    act(() => fire([visible(el, true)]));
    act(() => vi.advanceTimersByTime(READ_AFTER_MS));
    expect(api.recordView).toHaveBeenCalledTimes(1);
    expect(api.recordView).toHaveBeenCalledWith("p1");
  });
});
