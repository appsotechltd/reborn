import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { caughtUpIndex, Timeline } from "@/components/Timeline";
import { AuthProvider } from "@/lib/auth";
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
