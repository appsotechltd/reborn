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

    it("reacts from the one React button's picker, and picking the same one again clears it", async () => {
      const fetchMock = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>(async (url) =>
        String(url).endsWith("/v1/me") ? json(200, user) : new Response(null, { status: 204 }),
      );
      vi.stubGlobal("fetch", fetchMock);
      renderActions();
      const openPicker = () => {
        fireEvent.click(screen.getByTestId("post-react"));
        return screen.getByRole("group", { name: "Reactions" });
      };
      // One button with the total; the five reactions are in its picker, as in the app.
      expect(screen.getByTestId("post-react").getAttribute("aria-label")).toBe("React, 2 reactions");
      expect(within(openPicker()).getAllByRole("button")).toHaveLength(5);
      fireEvent.click(screen.getByRole("button", { name: "Insightful, 0" }));
      expect(screen.queryByRole("group", { name: "Reactions" })).toBeNull();
      const trigger = screen.getByTestId("post-react");
      expect(trigger.getAttribute("aria-label")).toBe("Your reaction: Insightful, 3 reactions");
      expect(trigger.textContent).toContain("💡");
      await waitFor(() =>
        expect(fetchMock.mock.calls.some(([u, i]) => String(u).endsWith("/reaction") && i?.method === "PUT")).toBe(true),
      );
      expect(within(openPicker()).getByRole("button", { name: "Insightful, 1" }).getAttribute("aria-pressed")).toBe("true");
      // Another reaction replaces it; picking the current one again clears it.
      fireEvent.click(screen.getByRole("button", { name: "Love, 2" }));
      expect(within(openPicker()).getByRole("button", { name: "Insightful, 0" }).getAttribute("aria-pressed")).toBe("false");
      const love = screen.getByRole("button", { name: "Love, 3" });
      expect(love.getAttribute("aria-pressed")).toBe("true");
      fireEvent.click(love);
      expect(screen.getByTestId("post-react").getAttribute("aria-label")).toBe("React, 2 reactions");
      await waitFor(() =>
        expect(fetchMock.mock.calls.some(([u, i]) => String(u).endsWith("/reaction") && i?.method === "DELETE")).toBe(true),
      );
    });

    it("closes the picker with Escape", () => {
      vi.stubGlobal("fetch", vi.fn(async (url: string) => (String(url).endsWith("/v1/me") ? json(200, user) : new Response(null, { status: 204 }))));
      renderActions();
      fireEvent.click(screen.getByTestId("post-react"));
      expect(screen.getByRole("group", { name: "Reactions" })).toBeTruthy();
      fireEvent.keyDown(document, { key: "Escape" });
      expect(screen.queryByRole("group", { name: "Reactions" })).toBeNull();
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
    expect(screen.getByTestId("post-react").textContent).toContain("2");
    fireEvent.click(screen.getByTestId("post-react"));
    expect(screen.getByRole("button", { name: "Like, 2" }).textContent).toContain("2");
    // Reactions nobody has used yet show no count.
    expect(screen.getByRole("button", { name: "Love, 0" }).textContent).toBe("❤️");
    expect(screen.getByRole("button", { name: /favourite.*5 favourites/i })).toBeTruthy();
    expect(screen.getByRole("link", { name: "3 comments" }).getAttribute("href")).toBe("/ideas/example-book--01#comments");
    expect(screen.getByRole("button", { name: /^Share.*shared 7 times$/ })).toBeTruthy();
    expect(screen.getByRole("button", { name: /^Gift\s*· 2/ })).toBeTruthy();
    expect(screen.getByRole("link", { name: /^Save to a collection/ })).toBeTruthy();
  });

  it("hides counts that are still zero", () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 204 })));
    const post = makePost({ stats: { reactions: {}, comments: 0, favorites: 0, shares: 0, gifts: 0 } });
    render(
      <AuthProvider>
        <PostActions post={post} />
      </AuthProvider>,
    );
    const actions = screen.getByTestId("post-actions");
    for (const el of actions.querySelectorAll("[aria-hidden=true]")) expect(el.textContent).not.toBe("0");
    expect(screen.getByRole("link", { name: "0 comments" }).textContent).toBe("0 comments"); // screen readers still hear it
  });

  it("sends signed-out visitors to sign in", () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 204 })));
    renderActions();
    fireEvent.click(screen.getByRole("button", { name: /favourite/i }));
    expect(push).toHaveBeenCalledWith("/signin?next=%2Fideas%2Fexample-book--01");
  });
});
