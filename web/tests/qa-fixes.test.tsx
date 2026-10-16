import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TopicPicker } from "@/app/welcome/WelcomeView";
import { AuthForm, welcomeHref } from "@/components/AuthForm";
import { ChipRow } from "@/components/ChipRow";
import { CardView } from "@/components/CardView";
import { PLAY_TIMEOUT_MS, resetPlayback } from "@/components/ExplainerVideo";
import { GiftButton } from "@/components/GiftButton";
import { StreakCard } from "@/components/StreakWidget";
import { ThemeSync } from "@/components/ThemeSync";
import { TrendingPosts } from "@/components/TrendingPosts";
import { createApiClient } from "@/lib/api";
import { AuthProvider } from "@/lib/auth";
import { isUuid } from "@/lib/content";
import { streakTodayText } from "@/lib/engage";
import { THEME_KEY } from "@/lib/theme";
import type { User } from "@/lib/types";
import { makeCard, makePost } from "./fixtures";

const push = vi.fn();
const notFound = vi.fn(() => {
  throw new Error("NEXT_NOT_FOUND");
});
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push, replace: vi.fn(), refresh: vi.fn() }),
  usePathname: () => "/",
  useSearchParams: () => new URLSearchParams(),
  notFound: () => notFound(),
}));

const server = vi.hoisted(() => ({
  getProfile: vi.fn(),
  getCircle: vi.fn(),
  getPublicStash: vi.fn(),
}));
vi.mock("@/lib/server-api", async () => {
  const real = await vi.importActual<typeof import("@/lib/server-api")>("@/lib/server-api");
  return {
    ...real,
    getProfile: server.getProfile,
    getCircle: server.getCircle,
    getPublicStash: server.getPublicStash,
    // Without Next's request scope, skip connection() and report the API as down.
    loadOr: async <T,>(load: () => Promise<T>, fallback: T) => {
      try {
        return { data: await load(), ok: true };
      } catch {
        return { data: fallback, ok: false };
      }
    },
  };
});

const user: User = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] } as unknown as User;
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
type Call = [string, RequestInit | undefined];

function stubApi(routes: (url: string, init?: RequestInit) => Response | undefined) {
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    const u = String(url);
    return routes(u, init) ?? (u.endsWith("/v1/me") ? json(200, user) : new Response(null, { status: 204 }));
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}
const calls = (f: ReturnType<typeof stubApi>) => f.mock.calls as unknown as Call[];
const signIn = (u: User = user) => window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user: u }));

beforeEach(() => {
  push.mockClear();
  notFound.mockClear();
});
afterEach(() => {
  window.localStorage.clear();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe("topic onboarding after sign-up", () => {
  it("sends a new account to the topic picker, then on to where it was going", async () => {
    expect(welcomeHref("/")).toBe("/welcome");
    expect(welcomeHref("/circles/abc")).toBe("/welcome?next=%2Fcircles%2Fabc");
    stubApi((u) => (u.endsWith("/v1/auth/register") ? json(201, { token: "t", user }) : undefined));
    render(
      <AuthProvider>
        <AuthForm mode="register" next="/" />
      </AuthProvider>,
    );
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Bea" } });
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "bea@example.org" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "password1" } });
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));
    await waitFor(() => expect(push).toHaveBeenCalledWith("/welcome"));
  });

  it("still sends a returning reader straight on after sign-in", async () => {
    stubApi((u) => (u.endsWith("/v1/auth/login") ? json(200, { token: "t", user }) : undefined));
    render(
      <AuthProvider>
        <AuthForm mode="signin" next="/favorites" />
      </AuthProvider>,
    );
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "bea@example.org" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "password1" } });
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }));
    await waitFor(() => expect(push).toHaveBeenCalledWith("/favorites"));
  });

  it("saves the picked topics to the account (PATCH /v1/me) and lands on the feed", async () => {
    signIn();
    const f = stubApi((u, init) =>
      u.endsWith("/v1/me") && init?.method === "PATCH"
        ? json(200, { ...user, topics: JSON.parse(String(init.body)).topics })
        : undefined,
    );
    render(
      <AuthProvider>
        <TopicPicker user={user} next="/" onboarding />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "Welcome to Reborn" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Skip" }).getAttribute("href")).toBe("/");
    expect(screen.getByRole("button", { name: "Show me everything" })).toBeTruthy();
    for (const name of ["Psychology", "Business", "Mindfulness & Philosophy"]) fireEvent.click(screen.getByRole("button", { name }));
    expect(screen.getByRole("button", { name: "Psychology" }).getAttribute("aria-pressed")).toBe("true");
    fireEvent.click(screen.getByRole("button", { name: "Business" })); // and off again
    fireEvent.click(screen.getByRole("button", { name: "Continue with 2" }));
    await waitFor(() => expect(push).toHaveBeenCalledWith("/"));
    const [, init] = calls(f).find(([u, i]) => u.endsWith("/v1/me") && i?.method === "PATCH")!;
    expect(JSON.parse(String(init?.body))).toEqual({ topics: ["psychology", "mindfulness"] });
    expect(JSON.parse(window.localStorage.getItem("reborn.auth")!).user.topics).toEqual(["psychology", "mindfulness"]);
  });

  it("opens from Settings with the account's topics and no Skip", async () => {
    signIn();
    const f = stubApi((u, init) => (u.endsWith("/v1/me") && init?.method === "PATCH" ? json(500, { error: { code: "x", message: "Server trouble" } }) : undefined));
    render(
      <AuthProvider>
        <TopicPicker user={{ ...user, topics: ["business"] }} next="/settings" onboarding={false} />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "Your topics" })).toBeTruthy();
    expect(screen.queryByRole("link", { name: "Skip" })).toBeNull();
    expect(screen.getByRole("link", { name: "Cancel" }).getAttribute("href")).toBe("/settings");
    expect(screen.getByRole("button", { name: "Business" }).getAttribute("aria-pressed")).toBe("true");
    fireEvent.click(screen.getByRole("button", { name: "Continue with 1" }));
    expect(await screen.findByRole("alert")).toBeTruthy();
    expect(push).not.toHaveBeenCalled();
    expect(calls(f).some(([u, i]) => u.endsWith("/v1/me") && i?.method === "PATCH")).toBe(true);
  });
});

describe("real 404s for unknown profiles, circles and stashes", () => {
  const params = <T,>(p: T) => ({ params: Promise.resolve(p) });

  it("404s an unknown handle, renders a known one, and leaves an API outage to the browser", async () => {
    const { default: ProfilePage } = await import("@/app/u/[handle]/page");
    server.getProfile.mockResolvedValueOnce(null);
    await expect(ProfilePage(params({ handle: "nobody" }))).rejects.toThrow("NEXT_NOT_FOUND");
    server.getProfile.mockResolvedValueOnce({ handle: "ada" });
    await expect(ProfilePage(params({ handle: "ada" }))).resolves.toBeTruthy();
    server.getProfile.mockRejectedValueOnce(new Error("down"));
    await expect(ProfilePage(params({ handle: "ada" }))).resolves.toBeTruthy();
  });

  it("404s an unknown circle", async () => {
    const { default: CirclePage } = await import("@/app/circles/[id]/page");
    server.getCircle.mockResolvedValueOnce(null);
    await expect(CirclePage(params({ id: "nope" }))).rejects.toThrow("NEXT_NOT_FOUND");
    server.getCircle.mockResolvedValueOnce({ id: "c1" });
    await expect(CirclePage(params({ id: "c1" }))).resolves.toBeTruthy();
  });

  it("404s a stash id that can't exist; a real-looking one asks to sign in, linking a public copy", async () => {
    expect(isUuid("cfa7101e-3ebd-4d5c-aeea-4c3b145e57cb")).toBe(true);
    expect(isUuid("does-not-exist")).toBe(false);
    const { default: StashPage } = await import("@/app/stashes/[id]/page");
    await expect(StashPage(params({ id: "does-not-exist" }))).rejects.toThrow("NEXT_NOT_FOUND");

    const id = "cfa7101e-3ebd-4d5c-aeea-4c3b145e57cb";
    server.getPublicStash.mockResolvedValueOnce({ stash: { id }, cards: [] });
    stubApi(() => undefined);
    render(<AuthProvider>{await StashPage(params({ id }))}</AuthProvider>);
    expect(await screen.findByRole("heading", { name: "Sign in to continue" })).toBeTruthy();
    expect(screen.getByText(/Collections are private to the account that made them/)).toBeTruthy();
    expect(screen.queryByText(/not found/i)).toBeNull();
    expect(screen.getByRole("link", { name: "Read the public collection" }).getAttribute("href")).toBe(`/s/${id}`);
  });
});

describe("theme on pages React renders from scratch (404s)", () => {
  it("re-applies the stored choice once mounted", () => {
    localStorage.setItem(THEME_KEY, "dark");
    document.documentElement.removeAttribute("data-theme"); // as when React rebuilds <html>
    render(<ThemeSync />);
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    document.documentElement.removeAttribute("data-theme");
  });
});

describe("Discover topic filter", () => {
  it("falls back to the topic's newest ideas when nothing is trending in it", async () => {
    const f = stubApi((u) => {
      if (u.includes("/v1/trending")) return json(200, { posts: [] });
      if (u.includes("/v1/timeline") && u.includes("topics=psychology"))
        return json(200, { posts: [makePost({ card: makeCard({ id: "example-book--09", title: "A psychology idea", topic: "psychology" }) })], next_cursor: null });
      return undefined;
    });
    render(
      <AuthProvider>
        <TrendingPosts initial={[makePost()]} />
      </AuthProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Psychology" }));
    expect(await screen.findByText("A psychology idea")).toBeTruthy();
    expect(screen.getByText("Nothing trending in Psychology this week yet. Here are its newest ideas.")).toBeTruthy();
    expect(screen.queryByText(/Nothing trending in this topic/)).toBeNull();
    const timeline = calls(f).find(([u]) => u.includes("/v1/timeline"))!;
    expect((timeline[1]?.headers as Record<string, string>)?.Authorization).toBeUndefined();
  });

  it("keeps the trending list when there is one", async () => {
    stubApi((u) =>
      u.includes("/v1/trending")
        ? json(200, { posts: [makePost({ card: makeCard({ id: "example-book--08", title: "Hot in business" }) })] })
        : undefined,
    );
    render(
      <AuthProvider>
        <TrendingPosts initial={[]} />
      </AuthProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Business" }));
    expect(await screen.findByText("Hot in business")).toBeTruthy();
    expect(screen.queryByText(/newest ideas/)).toBeNull();
  });
});

describe("gift dialog", () => {
  const tiers = [
    { id: "spark", name: "Spark", amount_cents: 199, currency: "usd" },
    { id: "lamp", name: "Lamp", amount_cents: 499, currency: "usd" },
  ];

  it("shows only the coming-soon notice, with no prices, while gifts are off", async () => {
    signIn();
    stubApi((u) => (u.endsWith("/v1/gifts/tiers") ? json(200, { tiers, providers: { stripe: false, apple: false, google: false } }) : undefined));
    render(
      <AuthProvider>
        <GiftButton postId="p1" title="An idea" />
      </AuthProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: /Gift/ }));
    const dialog = await screen.findByRole("dialog");
    expect(await within(dialog).findByText("Gifts are coming soon.")).toBeTruthy();
    expect(within(dialog).queryByText("Spark")).toBeNull();
    expect(within(dialog).queryByText("$1.99")).toBeNull();
  });

  it("lists the tiers when Stripe is on", async () => {
    signIn();
    stubApi((u) => (u.endsWith("/v1/gifts/tiers") ? json(200, { tiers, providers: { stripe: true, apple: false, google: false } }) : undefined));
    render(
      <AuthProvider>
        <GiftButton postId="p1" title="An idea" />
      </AuthProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: /Gift/ }));
    expect(await screen.findByRole("button", { name: /Spark/ })).toBeTruthy();
    expect(screen.queryByText("Gifts are coming soon.")).toBeNull();
  });
});

describe("streak wording", () => {
  it("never says more ideas 'of' the goal", () => {
    expect(streakTodayText({ today: 2, goal: 3, goal_met: false })).toBe("2 of 3 ideas today");
    expect(streakTodayText({ today: 0, goal: 1, goal_met: false })).toBe("0 of 1 idea today");
    expect(streakTodayText({ today: 3, goal: 3, goal_met: true })).toBe("Goal met · 3 ideas today (goal 3)");
    expect(streakTodayText({ today: 21, goal: 3, goal_met: true })).toBe("Goal met · 21 ideas today (goal 3)");
    expect(streakTodayText({ today: 1, goal: 1, goal_met: true })).toBe("Goal met · 1 idea today (goal 1)");
  });

  it("is what both streak cards show", () => {
    render(<StreakCard streak={{ current: 4, longest: 9, goal: 3, today: 21, goal_met: true, last_days: [] }} />);
    expect(screen.getAllByText("Goal met · 21 ideas today (goal 3)")).toHaveLength(2);
    expect(screen.queryByText(/21 of 3/)).toBeNull();
  });
});

describe("explainer video that can't play", () => {
  const explainer = {
    kind: "animated",
    video_url: "/media/explainers/example-book--01.mp4",
    poster_url: "/media/explainers/example-book--01.jpg",
    captions_url: null,
    duration_s: 52.4,
    width: 720,
    height: 1280,
    narrated: false,
  };
  beforeEach(() => resetPlayback());
  const playButton = () => screen.getByText("Play").closest("button")!;

  it("keeps the duration pill beside Play, off the poster's top corners", () => {
    render(<CardView card={makeCard({ explainer })} />);
    const pill = screen.getByTestId("explainer-duration");
    expect(pill.textContent).toContain("52 s");
    expect(pill.className).not.toMatch(/\b(top|right|left)-\d/);
    expect(pill.className).not.toContain("absolute");
    expect(pill.parentElement!.textContent).toContain("Play");
  });

  it("says so, with Try again and a link to the file, when the source fails", async () => {
    const play = vi.spyOn(HTMLMediaElement.prototype, "play").mockImplementation(() => Promise.resolve());
    const load = vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
    const { container } = render(<CardView card={makeCard({ explainer })} />);
    fireEvent.click(playButton());
    fireEvent.error(container.querySelector("video")!);
    const alert = await screen.findByRole("alert");
    expect(within(alert).getByText("This video can't play here")).toBeTruthy();
    expect(within(alert).getByRole("link", { name: "Open the video" }).getAttribute("href")).toMatch(/example-book--01\.mp4$/);
    fireEvent.click(within(alert).getByRole("button", { name: "Try again" }));
    expect(load).toHaveBeenCalled();
    expect(play).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("says so when the browser has no playable source", async () => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockImplementation(() =>
      Promise.reject(new DOMException("The element has no supported sources.", "NotSupportedError")),
    );
    render(<CardView card={makeCard({ explainer })} />);
    fireEvent.click(playButton());
    expect(await screen.findByText("This video can't play here")).toBeTruthy();
  });

  it("says so when nothing has played a while after pressing Play", async () => {
    vi.useFakeTimers();
    vi.spyOn(HTMLMediaElement.prototype, "play").mockImplementation(() => new Promise(() => {}));
    render(<CardView card={makeCard({ explainer })} />);
    fireEvent.click(playButton());
    await act(async () => {
      vi.advanceTimersByTime(PLAY_TIMEOUT_MS - 100);
    });
    expect(screen.queryByText("This video can't play here")).toBeNull();
    await act(async () => {
      vi.advanceTimersByTime(200);
    });
    expect(screen.getByText("This video can't play here")).toBeTruthy();
  });
});

describe("chip row scroll hint", () => {
  function sized(el: HTMLElement, { scrollWidth, clientWidth }: { scrollWidth: number; clientWidth: number }) {
    Object.defineProperty(el, "scrollWidth", { configurable: true, value: scrollWidth });
    Object.defineProperty(el, "clientWidth", { configurable: true, value: clientWidth });
  }

  it("fades the edge that has more chips beyond it", () => {
    render(
      <ChipRow label="Topics" scrollClassName="flex overflow-x-auto">
        <button type="button">One</button>
      </ChipRow>,
    );
    const row = screen.getByRole("group", { name: "Topics" });
    expect(row.hasAttribute("data-fade-end")).toBe(false);
    sized(row, { scrollWidth: 900, clientWidth: 390 });
    fireEvent.scroll(row);
    expect(row.hasAttribute("data-fade-end")).toBe(true);
    expect(row.hasAttribute("data-fade-start")).toBe(false);
    row.scrollLeft = 200;
    fireEvent.scroll(row);
    expect(row.hasAttribute("data-fade-start")).toBe(true);
    expect(row.hasAttribute("data-fade-end")).toBe(true);
    row.scrollLeft = 510;
    fireEvent.scroll(row);
    expect(row.hasAttribute("data-fade-end")).toBe(false);
  });
});

describe("tracking writes outlive the page", () => {
  it("sends seen batches and card views with keepalive, and nothing else", async () => {
    const f = vi.fn(async () => new Response(null, { status: 204 }));
    const api = createApiClient("http://api.test", () => "tok", f as unknown as typeof fetch);
    await api.markSeen(["a"]);
    await api.recordView("a");
    await api.setFavorite("a", true);
    const inits = (f.mock.calls as unknown as Call[]).map(([, i]) => i?.keepalive);
    expect(inits).toEqual([true, true, undefined]);
  });

  it("reads empty 204 bodies so the browser doesn't cancel (and report as aborted) a request that succeeded", async () => {
    const res = new Response(null, { status: 204 });
    const api = createApiClient("http://api.test", () => "tok", (async () => res) as unknown as typeof fetch);
    const read = vi.spyOn(res, "text");
    await expect(api.setFavorite("a", true)).resolves.toBeUndefined();
    expect(read).toHaveBeenCalled();
  });
});

describe("phone feed body fits whole lines only", () => {
  const LINE = 27;
  // Layout stand-in: two paragraphs (3 lines, then 2 lines after a 16px gap) starting at the body's top.
  function layout(room: { normal: number; shrunk: number }) {
    vi.stubGlobal("matchMedia", (q: string) => ({ matches: true, media: q, addEventListener() {}, removeEventListener() {} }));
    const realStyle = window.getComputedStyle;
    vi.spyOn(window, "getComputedStyle").mockImplementation((el: Element) =>
      el.hasAttribute("data-fit-lines") ? ({ lineHeight: `${LINE}px` } as CSSStyleDeclaration) : realStyle(el),
    );
    vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockImplementation(function (this: HTMLElement) {
      if (!this.hasAttribute("data-card-body")) return 0;
      return document.querySelector("[data-shrunk]") ? room.shrunk : room.normal;
    });
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
      const parent = this.parentElement;
      if (parent?.hasAttribute("data-fit-lines")) {
        const i = Array.from(parent.children).indexOf(this);
        const [top, height] = i === 0 ? [0, 3 * LINE] : [3 * LINE + 16, 2 * LINE];
        return { top, bottom: top + height, height } as DOMRect;
      }
      return { top: 0, bottom: 0, height: 0 } as DOMRect;
    });
  }
  const body = "First paragraph, three lines on a phone.\n\nSecond paragraph, two lines.";
  const preview = (disclaimer: string | null) =>
    render(<CardView card={makeCard({ body, disclaimer })} feed titleHref="/ideas/example-book--01" />).container;

  it("hides the body instead of showing a line cut through when not one line fits", () => {
    layout({ normal: 20, shrunk: 20 });
    const c = preview(null);
    const text = c.querySelector("[data-fit-lines]") as HTMLElement;
    expect(text.hasAttribute("data-empty")).toBe(true);
    expect(text.hasAttribute("data-clamped")).toBe(false);
    expect(text.style.getPropertyValue("-webkit-line-clamp")).toBe("");
  });

  it("lets the health note drop to one line so the body keeps two whole lines", () => {
    layout({ normal: 20, shrunk: 20 + 2 * LINE });
    const c = preview("Talk to a doctor before changing your routine.");
    const text = c.querySelector("[data-fit-lines]") as HTMLElement;
    expect(c.querySelector("[role=note] [data-fit-shrink]")!.hasAttribute("data-shrunk")).toBe(true);
    expect(text.hasAttribute("data-clamped")).toBe(true);
    expect(text.style.getPropertyValue("-webkit-line-clamp")).toBe("2");
  });

  it("gives the body room by shrinking the note even when it starts with none", () => {
    layout({ normal: 0, shrunk: LINE + 4 });
    const c = preview("Talk to a doctor before changing your routine.");
    const text = c.querySelector("[data-fit-lines]") as HTMLElement;
    expect(c.querySelector("[data-shrunk]")).toBeTruthy();
    expect(text.style.getPropertyValue("-webkit-line-clamp")).toBe("1");
    expect(text.hasAttribute("data-empty")).toBe(false);
  });

  it("leaves the note alone when the body already has two lines", () => {
    layout({ normal: 2 * LINE + 10, shrunk: 4 * LINE });
    const c = preview("Talk to a doctor before changing your routine.");
    expect(c.querySelector("[data-shrunk]")).toBeNull();
    expect((c.querySelector("[data-fit-lines]") as HTMLElement).style.getPropertyValue("-webkit-line-clamp")).toBe("2");
  });

  it("shows everything when it all fits", () => {
    layout({ normal: 400, shrunk: 400 });
    const c = preview("Note.");
    const text = c.querySelector("[data-fit-lines]") as HTMLElement;
    expect(text.hasAttribute("data-fits")).toBe(true);
    expect(c.querySelector("[data-shrunk]")).toBeNull();
  });
});
