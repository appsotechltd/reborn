import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PostActions } from "@/components/PostActions";
import { AuthProvider } from "@/lib/auth";
import { makePost } from "./fixtures";

const push = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push }),
  usePathname: () => "/ideas/example-book--01",
}));

const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function renderActions() {
  const post = makePost({ viewer: { reaction: null, favorited: false, seen: false } });
  render(
    <AuthProvider>
      <PostActions post={post} />
    </AuthProvider>,
  );
  return post;
}

describe("<PostActions>", () => {
  afterEach(() => {
    window.localStorage.clear();
    vi.unstubAllGlobals();
    push.mockReset();
  });

  describe("signed in", () => {
    beforeEach(() => {
      window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    });

    it("favourites optimistically and calls the API", async () => {
      let release: (r: Response) => void = () => {};
      const fetchMock = vi.fn((url: string, init?: RequestInit) => {
        if (String(url).endsWith("/v1/me")) return Promise.resolve(json(200, user));
        if (String(url).endsWith("/favorite") && init?.method === "PUT") return new Promise<Response>((r) => (release = r));
        return Promise.resolve(new Response(null, { status: 204 }));
      });
      vi.stubGlobal("fetch", fetchMock);
      renderActions();
      const heart = screen.getByRole("button", { name: /favourite/i });
      fireEvent.click(heart);
      // Updated before the server answers.
      expect(heart.getAttribute("aria-pressed")).toBe("true");
      expect(heart.textContent).toContain("6");
      release(new Response(null, { status: 204 }));
      await waitFor(() =>
        expect(fetchMock.mock.calls.some(([u, i]) => String(u).endsWith("/v1/posts/example-book--01/favorite") && i?.method === "PUT")).toBe(true),
      );
    });

    it("rolls back when the API fails", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(async (url: string) =>
          String(url).endsWith("/v1/me") ? json(200, user) : json(500, { error: { code: "internal", message: "boom" } }),
        ),
      );
      renderActions();
      const heart = screen.getByRole("button", { name: /favourite/i });
      fireEvent.click(heart);
      expect(await screen.findByRole("alert")).toBeTruthy();
      expect(heart.getAttribute("aria-pressed")).toBe("false");
      expect(heart.textContent).toContain("5");
    });

    it("reacts, and tapping the same reaction again clears it", async () => {
      const fetchMock = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(async (url) =>
        String(url).endsWith("/v1/me") ? json(200, user) : new Response(null, { status: 204 }),
      );
      vi.stubGlobal("fetch", fetchMock);
      renderActions();
      // Every reaction is one tap away, with its count, as in the app.
      const group = screen.getByRole("group", { name: "Reactions" });
      expect(within(group).getAllByRole("button")).toHaveLength(5);
      fireEvent.click(screen.getByRole("button", { name: "Insightful, 0" }));
      const active = screen.getByRole("button", { name: "Insightful, 1" });
      expect(active.getAttribute("aria-pressed")).toBe("true");
      await waitFor(() =>
        expect(fetchMock.mock.calls.some(([u, i]) => String(u).endsWith("/reaction") && i?.method === "PUT")).toBe(true),
      );
      // Another reaction replaces it; tapping the current one again clears it.
      fireEvent.click(screen.getByRole("button", { name: "Love, 2" }));
      expect(screen.getByRole("button", { name: "Insightful, 0" }).getAttribute("aria-pressed")).toBe("false");
      expect(screen.getByRole("button", { name: "Love, 3" }).getAttribute("aria-pressed")).toBe("true");
      fireEvent.click(screen.getByRole("button", { name: "Love, 3" }));
      expect(screen.getByRole("button", { name: "Love, 2" }).getAttribute("aria-pressed")).toBe("false");
      await waitFor(() =>
        expect(fetchMock.mock.calls.some(([u, i]) => String(u).endsWith("/reaction") && i?.method === "DELETE")).toBe(true),
      );
    });
  });

  it("shows favourite, comment, share and gift counts with names for screen readers", () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 204 })));
    const post = makePost({ stats: { reactions: { like: 2 }, comments: 3, favorites: 5, shares: 7, gifts: 2 } });
    render(
      <AuthProvider>
        <PostActions post={post} />
      </AuthProvider>,
    );
    expect(screen.getByRole("button", { name: "Like, 2" })).toBeTruthy();
    expect(screen.getByRole("button", { name: /favourite.*5 favourites/i })).toBeTruthy();
    expect(screen.getByRole("link", { name: "3 comments" }).getAttribute("href")).toBe("/ideas/example-book--01#comments");
    expect(screen.getByRole("button", { name: /^Share.*shared 7 times$/ })).toBeTruthy();
    expect(screen.getByRole("button", { name: /^Gift\s*· 2/ })).toBeTruthy();
  });

  it("sends signed-out visitors to sign in", () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 204 })));
    renderActions();
    fireEvent.click(screen.getByRole("button", { name: /favourite/i }));
    expect(push).toHaveBeenCalledWith("/signin?next=%2Fideas%2Fexample-book--01");
  });
});
