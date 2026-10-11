import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { caughtUpIndex, Timeline } from "@/components/Timeline";
import { AuthProvider } from "@/lib/auth";
import { READ_AFTER_MS } from "@/lib/use-seen";
import { FakeIO, installFakeIO, setVisible } from "./fake-io";
import { makeCard, makePost } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
}));

const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const post = (n: number, seen: boolean, reason = { kind: "author", label: "Ada Example" }) =>
  makePost({
    card: makeCard({ id: `example-book--0${n}`, title: `Idea ${n}` }),
    viewer: { reaction: null, favorited: false, seen },
    reason,
  });

describe("caughtUpIndex", () => {
  it("finds where unseen posts end", () => {
    expect(caughtUpIndex([post(1, false), post(2, false), post(3, true)])).toBe(2);
    expect(caughtUpIndex([post(1, false)])).toBe(-1);
  });
});

describe("<Timeline>", () => {
  afterEach(() => {
    window.localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("shows the signed-in timeline with reasons and the caught-up divider", async () => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    const posts = [post(1, false), post(2, true, { kind: "favorite", label: "Bob" })];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) =>
        String(url).endsWith("/v1/me") ? json(200, user) : json(200, { posts, next_cursor: null }),
      ),
    );
    render(
      <AuthProvider>
        <Timeline initialPosts={[]} initialCursor={null} />
      </AuthProvider>,
    );
    expect(await screen.findByText("Because you follow Ada Example")).toBeTruthy();
    expect(screen.getByText("Bob favourited this")).toBeTruthy();
    expect(screen.getByRole("separator", { name: "You're all caught up" })).toBeTruthy();
    // Credit is still on every post.
    expect(screen.getAllByTestId("card-credit")).toHaveLength(2);
  });

  it("works signed out with a sign-up prompt", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(200, { posts: [], next_cursor: null })));
    render(
      <AuthProvider>
        <Timeline initialPosts={[post(1, false)]} initialCursor={null} />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "Idea 1" })).toBeTruthy();
    expect(await screen.findByRole("link", { name: "Create an account" })).toBeTruthy();
    expect(screen.queryByRole("separator")).toBeNull();
  });
});

describe("<Timeline> endless loading", () => {
  afterEach(() => {
    // Restore even when a test fails midway, so fake timers and spies never leak into the next test.
    vi.useRealTimers();
    vi.restoreAllMocks();
    window.localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("keeps loading past the unseen posts into older ones, retries a failed page and never dead-ends", async () => {
    installFakeIO();
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    let failNext = true;
    const calls: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string) => {
        const url = String(input);
        if (url.endsWith("/v1/me")) return json(200, user);
        if (!url.includes("/v1/timeline")) return json(204, {});
        const cursor = new URL(url).searchParams.get("cursor");
        calls.push(cursor ?? "first");
        if (!cursor) return json(200, { posts: [post(1, false), post(2, false)], next_cursor: "c1" });
        // The API carries on past the unseen posts with the ones already seen.
        if (cursor === "c1") return json(200, { posts: [post(3, true), post(4, true)], next_cursor: "c2" });
        if (failNext) {
          failNext = false;
          return json(500, { error: { code: "internal", message: "Something went wrong." } });
        }
        return json(200, { posts: [post(5, true)], next_cursor: null });
      }),
    );
    render(
      <AuthProvider>
        <Timeline initialPosts={[]} initialCursor={null} />
      </AuthProvider>,
    );
    expect(await screen.findByRole("heading", { name: "Idea 1" })).toBeTruthy();

    // The sentinel is in range (it preloads about three screens ahead) and stays in range:
    // each finished page re-arms it, so the next one loads without another scroll.
    const sentinel = screen.getByTestId("load-more");
    expect(FakeIO.all.size).toBeGreaterThan(0);
    expect([...FakeIO.all].some((io) => io.options?.rootMargin === "0px 0px 300% 0px")).toBe(true);
    await act(async () => setVisible(sentinel, 1));

    expect(await screen.findByRole("heading", { name: "Idea 4" })).toBeTruthy();
    expect(screen.getByRole("separator", { name: "You're all caught up" })).toBeTruthy();

    // c2 fails: a retry, not a stop, and no automatic hammering.
    expect(await screen.findByRole("button", { name: "Try again" })).toBeTruthy();
    expect(screen.getByRole("alert").textContent).toMatch(/went wrong/i);
    expect(calls).toEqual(["first", "c1", "c2"]);

    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByRole("heading", { name: "Idea 5" })).toBeTruthy();
    expect(calls).toEqual(["first", "c1", "c2", "c2"]);
    // At the true end there is still somewhere to go.
    expect(screen.getByRole("link", { name: "Discover more ideas" })).toBeTruthy();
    expect(screen.queryByTestId("load-more")).toBeNull();
  });

  it("counts a post in the snap feed as read after 8 seconds on screen, while its video autoplays", async () => {
    installFakeIO();
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    const views: string[] = [];
    const videoPost = makePost({
      card: makeCard({
        id: "example-book--01",
        title: "Idea 1",
        explainer: {
          kind: "animated",
          video_url: "/media/explainers/example-book--01.mp4",
          poster_url: "/media/explainers/example-book--01.jpg",
          captions_url: null,
          duration_s: 40,
          width: 720,
          height: 1280,
          narrated: false,
        },
      }),
      viewer: { reaction: null, favorited: false, seen: false },
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string) => {
        const url = String(input);
        if (url.endsWith("/v1/me")) return json(200, user);
        if (url.includes("/view")) {
          views.push(url);
          return new Response(null, { status: 204 });
        }
        if (url.includes("/v1/seen")) return new Response(null, { status: 204 });
        return json(200, { posts: [videoPost, post(2, false)], next_cursor: null });
      }),
    );
    const play = vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    const { container } = render(
      <AuthProvider>
        <Timeline initialPosts={[]} initialCursor={null} />
      </AuthProvider>,
    );
    await screen.findByRole("heading", { name: "Idea 1" });
    // Let the signed-in refresh settle, then bring the video on screen: it autoplays.
    await waitFor(() => {
      act(() => setVisible(container.querySelector("video")!, 1));
      expect(play).toHaveBeenCalledTimes(1);
    });
    vi.useFakeTimers();
    const slide = container.querySelector('[data-post-id="example-book--01"]')!;
    act(() => setVisible(slide, 1));
    act(() => vi.advanceTimersByTime(READ_AFTER_MS - 100));
    expect(views).toHaveLength(0);
    act(() => vi.advanceTimersByTime(200));
    await act(async () => {});
    expect(views).toHaveLength(1);
    expect(views[0]).toMatch(/\/v1\/cards\/example-book--01\/view$/);
  });
});
