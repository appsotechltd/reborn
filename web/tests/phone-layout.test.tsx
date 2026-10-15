import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CardView } from "@/components/CardView";
import { PostCard } from "@/components/PostCard";
import { TabBar } from "@/components/TabBar";
import { Timeline } from "@/components/Timeline";
import { AuthProvider } from "@/lib/auth";
import { installFakeIO } from "./fake-io";
import { makeCard, makePost } from "./fixtures";

let pathname = "/";
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => pathname,
}));

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

describe("<TabBar>", () => {
  it("has the app's five tabs, marks the current one and is phones only", () => {
    pathname = "/stashes/abc";
    render(<TabBar />);
    const nav = screen.getByRole("navigation", { name: "Tabs" });
    expect(nav.className).toContain("md:hidden");
    expect(nav.className).toContain("fixed");
    const links = within(nav).getAllByRole("link");
    expect(links.map((l) => l.textContent)).toEqual(["Home", "Discover", "Collections", "Review", "Ask"]);
    expect(links.map((l) => l.getAttribute("href"))).toEqual(["/", "/discover", "/stashes", "/review", "/ask"]);
    expect(within(nav).getByRole("link", { name: "Collections" }).getAttribute("aria-current")).toBe("page");
    expect(within(nav).getByRole("link", { name: "Home" }).getAttribute("aria-current")).toBeNull();
  });

  it("counts the quiz as Review and only / as Home", () => {
    pathname = "/quiz";
    render(<TabBar />);
    expect(screen.getByRole("link", { name: "Review" }).getAttribute("aria-current")).toBe("page");
    expect(screen.getByRole("link", { name: "Home" }).getAttribute("aria-current")).toBeNull();
  });
});

describe("phone feed", () => {
  const posts = [1, 2].map((n) => makePost({ card: makeCard({ id: `example-book--0${n}`, title: `Idea ${n}` }) }));

  beforeEach(() => {
    pathname = "/";
    installFakeIO();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    window.localStorage.clear();
  });

  it("filters the feed in place with the topic chips, For you first", async () => {
    const calls: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string) => {
        const url = String(input);
        calls.push(url);
        if (url.includes("/v1/timeline") && url.includes("topics=health")) {
          return json(200, { posts: [makePost({ card: makeCard({ id: "example-book--07", title: "Health idea" }) })], next_cursor: null });
        }
        return json(200, { posts: [], next_cursor: null });
      }),
    );
    vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    render(
      <AuthProvider>
        <Timeline initialPosts={posts} initialCursor={null} topics={[{ slug: "health", name: "Health" }]} />
      </AuthProvider>,
    );
    const chips = screen.getByRole("group", { name: "Filter the timeline by topic" });
    // The sticky box wraps the scrolling row (and its edge fades).
    expect(chips.parentElement!.className).toContain("md:hidden");
    expect(chips.parentElement!.className).toContain("sticky");
    expect(chips.parentElement!.hasAttribute("data-feed-chips")).toBe(true);
    const forYou = within(chips).getByRole("button", { name: "For you" });
    expect(forYou.getAttribute("aria-pressed")).toBe("true");
    fireEvent.click(within(chips).getByRole("button", { name: "Health" }));
    expect(await screen.findByRole("heading", { name: "Health idea" })).toBeTruthy();
    expect(calls.some((u) => u.includes("/v1/timeline") && u.includes("topics=health"))).toBe(true);
    expect(within(chips).getByRole("button", { name: "Health" }).getAttribute("aria-pressed")).toBe("true");
    expect(screen.queryByRole("heading", { name: "Idea 1" })).toBeNull();
  });

  it("puts today's idea and the swipe hint in the first slide", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string) =>
        String(input).endsWith("/v1/daily")
          ? json(200, { date: "2026-10-11", card: makeCard({ id: "example-book--05", title: "Daily one" }) })
          : json(200, { posts: [], next_cursor: null }),
      ),
    );
    render(
      <AuthProvider>
        <Timeline initialPosts={posts} initialCursor={null} />
      </AuthProvider>,
    );
    const daily = await screen.findByTestId("daily-banner");
    expect(daily.getAttribute("href")).toBe("/ideas/example-book--05");
    expect(daily.textContent).toContain("Daily one");
    const first = screen.getByRole("list", { name: "Timeline" }).querySelector("li")!;
    expect(first.contains(daily)).toBe(true);
    expect(first.textContent).toContain("Swipe up for the next idea");
    await waitFor(() => expect(screen.getByRole("link", { name: "Create an account" })).toBeTruthy());
    expect(first.contains(screen.getByRole("link", { name: "Create an account" }))).toBe(true);
  });

  it("previews a post like the app: reason with icon, amber source line, Read more pill, actions under the card", () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(200, {})));
    const post = makePost({ reason: { kind: "topic", label: "Personal Development" } });
    const { container } = render(
      <AuthProvider>
        <PostCard post={post} showReason snap />
      </AuthProvider>,
    );
    const reason = screen.getByTestId("post-reason");
    expect(reason.textContent).toBe("In Personal Development, one of your topics");
    expect(reason.querySelector("svg")).toBeTruthy();
    const source = screen.getByRole("link", { name: "An Example Book" });
    expect(source.className).toContain("text-accent-text");
    expect(screen.getByTestId("card-byline").textContent).toContain(" · ");
    const readMore = screen.getByRole("link", { name: "Read more: Small steps beat big plans" });
    expect(readMore.className).toContain("btn-primary");
    // The body is cut to whole lines by FitBody (data-fit-lines), never scrolled.
    expect(container.querySelector("[data-card-body] [data-fit-lines]")).toBeTruthy();
    // On phones the actions sit under the card, outside its box.
    const actions = screen.getByTestId("post-actions");
    const box = container.querySelector("[data-card-preview]")!.parentElement!;
    expect(box.contains(actions)).toBe(false);
    expect(box.className).toContain("max-md:rounded-card");
  });

  it("names the source and authors for screen readers on the card page", () => {
    render(<CardView card={makeCard()} />);
    expect(screen.getByTestId("card-byline").textContent).toBe("From An Example Book ·  by Ada Example · Chapter 1");
  });
});
