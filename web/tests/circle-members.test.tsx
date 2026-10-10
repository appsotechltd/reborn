import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { CircleView } from "@/app/circles/[id]/CircleView";
import { AuthProvider } from "@/lib/auth";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  usePathname: () => "/circles/k1",
}));

const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const owner = { id: "o1", handle: "olive", display_name: "Olive", role: "owner", joined_at: "2026-10-01T00:00:00Z" };
const circle = (isMember: boolean, members: number) => ({
  id: "k1",
  name: "Stoics at dawn",
  description: "",
  source: { id: "example-book", title: "An Example Book" },
  owner: { id: "o1", handle: "olive", display_name: "Olive" },
  members,
  is_member: isMember,
  role: isMember ? "member" : null,
  created_at: "2026-10-01T00:00:00Z",
});

afterEach(() => {
  window.localStorage.clear();
  vi.unstubAllGlobals();
});

describe("circle members", () => {
  it("lists members with an owner marker and refreshes after joining", async () => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    let joined = false;
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u.endsWith("/v1/me")) return json(200, user);
      if (u.endsWith("/v1/circles/k1/join") && init?.method === "POST") {
        joined = true;
        return json(200, circle(true, 2));
      }
      if (u.endsWith("/v1/circles/k1/members"))
        return json(200, {
          members: joined ? [owner, { id: "u1", handle: "ada", display_name: "Ada", role: "member", joined_at: "2026-10-10T00:00:00Z" }] : [owner],
        });
      if (u.endsWith("/v1/circles/k1")) return json(200, circle(joined, joined ? 2 : 1));
      if (u.includes("/v1/circles/k1/messages")) return json(200, { messages: [] });
      if (u.includes("/v1/sources/")) return json(200, { source: {}, cards: [] });
      return new Response(null, { status: 204 });
    });
    vi.stubGlobal("fetch", fetchMock);
    render(
      <AuthProvider>
        <CircleView id="k1" />
      </AuthProvider>,
    );
    const section = await screen.findByRole("region", { name: /Members/ });
    const olive = await within(section).findByRole("link", { name: /Olive/ });
    expect(olive.getAttribute("href")).toBe("/u/olive");
    expect(olive.textContent).toContain("owner");
    expect(within(section).queryByRole("link", { name: /Ada/ })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Join circle" }));
    const ada = await within(section).findByRole("link", { name: /Ada/ });
    expect(ada.getAttribute("href")).toBe("/u/ada");
    expect(ada.textContent).not.toContain("owner");
    await waitFor(() =>
      expect(fetchMock.mock.calls.filter(([u]) => String(u).endsWith("/v1/circles/k1/members")).length).toBeGreaterThanOrEqual(2),
    );
  });
});
