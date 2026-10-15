import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PostCard } from "@/components/PostCard";
import { Timeline } from "@/components/Timeline";
import { AuthProvider } from "@/lib/auth";
import { currentSlide, keyDirection } from "@/lib/use-snap-feed";
import { installFakeIO, stubMatchMedia } from "./fake-io";
import { makeCard, makePost } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
}));

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const posts = [1, 2, 3, 4, 5].map((n) => makePost({ card: makeCard({ id: `example-book--0${n}`, title: `Idea ${n}` }) }));

describe("keyDirection", () => {
  it("maps j/k, the arrows and page keys to one post down or up", () => {
    for (const k of ["ArrowDown", "PageDown", "j"]) expect(keyDirection(k)).toBe(1);
    for (const k of ["ArrowUp", "PageUp", "k"]) expect(keyDirection(k)).toBe(-1);
    for (const k of ["Enter", " ", "J", "Tab"]) expect(keyDirection(k)).toBe(0);
  });
});

describe("currentSlide", () => {
  it("is the last slide whose top has reached the header", () => {
    expect(currentSlide([-1400, -700, 0, 700])).toBe(2);
    expect(currentSlide([-703, -3, 697])).toBe(1); // within the snapping tolerance
  });
  it("is -1 while the intro above the feed is showing", () => {
    expect(currentSlide([300, 1000])).toBe(-1);
  });
});

describe("snap feed keyboard navigation", () => {
  const SLIDE = 700;
  let scrollY = 0;
  let scrolled: { index: number; opts: ScrollIntoViewOptions | undefined }[] = [];

  beforeEach(() => {
    installFakeIO();
    scrollY = 0;
    scrolled = [];
    vi.stubGlobal("fetch", vi.fn(async () => json(200, { posts: [], next_cursor: null })));
    // Slides stack one screen apart below a 100px intro; scrollIntoView "moves" there at once.
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
      const li = this.closest("[data-snap-feed] > li");
      if (li && li === this) {
        const i = Array.from(li.parentElement!.children).indexOf(li);
        const top = 100 + i * SLIDE - scrollY;
        return { top, bottom: top + SLIDE, height: SLIDE, left: 0, right: 375, width: 375, x: 0, y: top, toJSON() {} };
      }
      return { top: 0, bottom: 0, height: 0, left: 0, right: 0, width: 0, x: 0, y: 0, toJSON() {} };
    });
    Element.prototype.scrollIntoView = vi.fn(function (this: Element, opts?: boolean | ScrollIntoViewOptions) {
      const i = Array.from(this.parentElement!.children).indexOf(this);
      scrolled.push({ index: i, opts: typeof opts === "object" ? opts : undefined });
      scrollY = 100 + i * SLIDE;
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  function renderFeed() {
    render(
      <AuthProvider>
        <Timeline initialPosts={posts} initialCursor={null} />
      </AuthProvider>,
    );
  }

  it("moves exactly one post per key: j/ArrowDown/PageDown down, k/ArrowUp up", () => {
    stubMatchMedia({ "max-width": true });
    renderFeed();
    vi.spyOn(Date, "now").mockReturnValue(0);
    let now = 0;
    const press = (key: string) => {
      now += 1000; // let each move settle
      vi.mocked(Date.now).mockReturnValue(now);
      fireEvent.keyDown(document.body, { key });
    };
    press("j"); // from the intro to the first post
    press("ArrowDown");
    press("PageDown");
    press("k");
    press("ArrowUp");
    expect(scrolled.map((s) => s.index)).toEqual([0, 1, 2, 1, 0]);
    expect(scrolled[0].opts).toEqual({ block: "start", behavior: "smooth" });
    // Focus follows the post on screen.
    expect(document.activeElement?.textContent).toBe("Idea 1");
  });

  it("keeps going on quick presses while a smooth scroll is still moving", () => {
    stubMatchMedia({ "max-width": true });
    renderFeed();
    vi.spyOn(Date, "now").mockReturnValue(5000);
    Element.prototype.scrollIntoView = vi.fn(function (this: Element) {
      scrolled.push({ index: Array.from(this.parentElement!.children).indexOf(this), opts: undefined });
      // still mid-scroll: the page hasn't moved yet
    });
    fireEvent.keyDown(document.body, { key: "j" });
    fireEvent.keyDown(document.body, { key: "j" });
    fireEvent.keyDown(document.body, { key: "j" });
    expect(scrolled.map((s) => s.index)).toEqual([0, 1, 2]);
  });

  it("does not smooth-scroll when the reader prefers reduced motion", () => {
    stubMatchMedia({ "max-width": true, "prefers-reduced-motion": true });
    renderFeed();
    fireEvent.keyDown(document.body, { key: "j" });
    expect(scrolled[0].opts).toEqual({ block: "start", behavior: "auto" });
  });

  it("leaves keys alone on wider screens, while typing, and with modifiers", () => {
    stubMatchMedia({ "max-width": false });
    renderFeed();
    fireEvent.keyDown(document.body, { key: "j" });
    expect(scrolled).toEqual([]);

    vi.unstubAllGlobals();
    stubMatchMedia({ "max-width": true });
    const input = document.createElement("input");
    document.body.appendChild(input);
    fireEvent.keyDown(input, { key: "j" });
    fireEvent.keyDown(document.body, { key: "j", ctrlKey: true });
    expect(scrolled).toEqual([]);
    input.remove();
  });

  it("lets ArrowUp from the first post go back to the intro (the browser's own scroll)", () => {
    stubMatchMedia({ "max-width": true });
    renderFeed();
    fireEvent.keyDown(document.body, { key: "j" });
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 5000);
    const up = fireEvent.keyDown(document.body, { key: "ArrowUp" });
    expect(up).toBe(true); // not prevented
    expect(scrolled.map((s) => s.index)).toEqual([0]);
  });

  it("renders the feed as snap slides with the actions pinned", () => {
    stubMatchMedia({ "max-width": true });
    renderFeed();
    const list = screen.getByRole("list", { name: "Timeline" });
    expect(list.hasAttribute("data-snap-feed")).toBe(true);
    const slide = list.querySelector("li")!;
    expect(slide.className).toContain("max-md:snap-start");
    expect(slide.className).toContain("max-md:snap-always");
    expect(slide.className).toContain("max-md:h-[var(--slide-h)]");
    expect(screen.getAllByTestId("post-actions")[0].className).toContain("max-md:shrink-0");
  });

  it("has no scroll container inside a slide, so a swipe always moves to the next post", () => {
    stubMatchMedia({ "max-width": true });
    renderFeed();
    const list = screen.getByRole("list", { name: "Timeline" });
    expect(list.querySelector("[data-slide-scroll]")).toBeNull();
    for (const el of list.querySelectorAll<HTMLElement>("*")) {
      expect(el.getAttribute("class") ?? "").not.toMatch(/overflow(-y)?-(auto|scroll)\b/);
    }
  });

  it("moves to the next post with the arrow keys while Read the idea has focus", () => {
    stubMatchMedia({ "max-width": true });
    renderFeed();
    fireEvent.keyDown(document.body, { key: "j" });
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 5000);
    const readMore = screen.getAllByRole("link", { name: /^Read the idea/ })[0];
    readMore.focus();
    expect(document.activeElement).toBe(readMore);
    const down = fireEvent.keyDown(readMore, { key: "ArrowDown" });
    expect(down).toBe(false); // handled: moved a post, not scrolled
    expect(scrolled.map((s) => s.index)).toEqual([0, 1]);
    expect(document.activeElement?.textContent).toBe("Idea 2");
  });
});

describe("snap feed preview", () => {
  const video = {
    kind: "animated" as const,
    video_url: "/media/explainers/example-book--09.mp4",
    poster_url: "/media/explainers/example-book--09.jpg",
    captions_url: null,
    duration_s: 40,
    width: 720,
    height: 1280,
    narrated: false,
  };

  beforeEach(() => {
    installFakeIO();
    vi.stubGlobal("fetch", vi.fn(async () => json(200, { posts: [], next_cursor: null })));
  });
  afterEach(() => vi.unstubAllGlobals());

  const renderCard = (post: (typeof posts)[number], snap = false) =>
    render(
      <AuthProvider>
        <PostCard post={post} snap={snap} />
      </AuthProvider>,
    );

  it("clamps the body to the slide, fades it at the cut and leaves the rest to the card page", () => {
    const { container } = renderCard(posts[0], true);
    const article = container.querySelector("article")!;
    expect(article.hasAttribute("data-card-preview")).toBe(true);
    expect(article.className).toContain("max-md:flex-col");
    // Topic, title and source stay.
    expect(screen.getByRole("link", { name: "Personal Development" })).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Idea 1" }).className).toContain("max-md:line-clamp-3");
    expect(screen.getByRole("link", { name: "An Example Book" })).toBeTruthy();
    // The body takes what space is left, clipped (never scrolled) and faded at the bottom.
    const body = container.querySelector<HTMLElement>("[data-card-body]")!;
    expect(body.className).toContain("max-md:flex-1");
    expect(body.className).toContain("max-md:min-h-0");
    expect(body.className).toContain("max-md:overflow-clip");
    expect(body.className).toMatch(/max-md:\[mask-image:linear-gradient\(to_bottom/);
    // Apply it is on the card page only (on phones).
    expect(screen.getByRole("region", { name: "Apply it" }).className).toContain("max-md:hidden");
  });

  it("always offers Read the idea on phones, linking to the card's page", () => {
    renderCard(posts[0], true);
    const link = screen.getByRole("link", { name: "Read the idea: Idea 1" });
    expect(link.getAttribute("href")).toBe("/ideas/example-book--01");
    expect(link.parentElement!.className).toContain("md:hidden"); // tablets and desktops show the full card
    expect(link.tabIndex).not.toBe(-1);
  });

  it("puts the video first with the title under it and Read the idea when there is body text", () => {
    const post = makePost({ card: makeCard({ id: "example-book--09", title: "Watch this", explainer: video }) });
    const { container } = renderCard(post, true);
    const figure = screen.getByTestId("explainer");
    expect(figure.className).toContain("max-md:order-first");
    expect(figure.className).toContain("max-md:flex-1");
    expect(figure.firstElementChild!.getAttribute("style")).toContain("aspect-ratio: 720 / 1280");
    expect(screen.getByRole("heading", { name: "Watch this" }).className).toContain("max-md:line-clamp-2");
    expect(container.querySelector("[data-card-body]")!.className).toContain("max-md:hidden");
    expect(screen.getByRole("link", { name: "Read the idea: Watch this" }).getAttribute("href")).toBe("/ideas/example-book--09");
  });

  it("leaves Read the idea off a video post with no body text", () => {
    const post = makePost({ card: makeCard({ id: "example-book--09", title: "Watch this", body: " ", explainer: video }) });
    renderCard(post, true);
    expect(screen.queryByRole("link", { name: /^Read the idea/ })).toBeNull();
  });

  it("shows the full card outside the home feed", () => {
    const { container } = renderCard(posts[0]);
    expect(container.querySelector("[data-card-preview]")).toBeNull();
    expect(screen.queryByRole("link", { name: /^Read the idea/ })).toBeNull();
    expect(container.querySelector("[data-card-body]")!.className).not.toContain("max-md:");
    expect(screen.getByRole("region", { name: "Apply it" }).className).not.toContain("max-md:hidden");
  });
});
