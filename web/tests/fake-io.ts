import { vi } from "vitest";

type Callback = (entries: Partial<IntersectionObserverEntry>[]) => void;

/**
 * A stand-in IntersectionObserver that remembers every live observer and what it
 * watches, so a test can say "this element is now N% on screen" and only the
 * observers watching it hear about it.
 */
export class FakeIO {
  static all = new Set<FakeIO>();
  /** Last visibility set per element; like a real observer, a new one reports it on observe(). */
  static ratios = new Map<Element, number>();
  els = new Set<Element>();
  constructor(
    public cb: Callback,
    public options?: IntersectionObserverInit,
  ) {
    FakeIO.all.add(this);
  }
  observe(el: Element) {
    this.els.add(el);
    const ratio = FakeIO.ratios.get(el);
    if (ratio !== undefined) queueMicrotask(() => this.els.has(el) && this.cb([entryFor(el, ratio)]));
  }
  unobserve(el: Element) {
    this.els.delete(el);
  }
  disconnect() {
    this.els.clear();
    FakeIO.all.delete(this);
  }
  takeRecords() {
    return [];
  }
}

function entryFor(el: Element, ratio: number): Partial<IntersectionObserverEntry> {
  return {
    target: el,
    isIntersecting: ratio > 0,
    intersectionRatio: ratio,
    intersectionRect: { height: 800 * ratio } as DOMRectReadOnly,
    rootBounds: { height: 800 } as DOMRectReadOnly,
  };
}

/** Tell the observers watching `el` that `ratio` of it is visible (0 = off screen). */
export function setVisible(el: Element, ratio: number) {
  FakeIO.ratios.set(el, ratio);
  for (const io of [...FakeIO.all]) if (io.els.has(el)) io.cb([entryFor(el, ratio)]);
}

export function installFakeIO() {
  FakeIO.all.clear();
  FakeIO.ratios.clear();
  vi.stubGlobal("IntersectionObserver", FakeIO);
}

/** matchMedia that answers `matches` per query substring. */
export function stubMatchMedia(answers: Record<string, boolean>) {
  vi.stubGlobal(
    "matchMedia",
    vi.fn((query: string) => ({
      matches: Object.entries(answers).some(([k, v]) => v && query.includes(k)),
      media: query,
      addEventListener() {},
      removeEventListener() {},
      addListener() {},
      removeListener() {},
      onchange: null,
      dispatchEvent: () => false,
    })),
  );
}
