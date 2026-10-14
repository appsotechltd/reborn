import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SummaryPost } from "@/components/SummaryPost";
import { SummaryReader } from "@/components/SummaryReader";
import { Timeline, cardPosts } from "@/components/Timeline";
import { AuthProvider } from "@/lib/auth";
import {
  coverageLabel,
  localProgress,
  resumeIndex,
  saveLocalProgress,
  summaryByline,
  summaryHref,
  summaryMeta,
} from "@/lib/summaries";
import type { Summary, SummaryDetail, SummaryItem } from "@/lib/types";
import { makeCard, makePost } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
}));

const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function makeSummary(overrides: Partial<Summary> = {}): Summary {
  return {
    id: "example-book",
    kind: "book",
    title: "An Example Book",
    description: "Every idea from An Example Book, in 3 one-minute parts.",
    topic: "personal-development",
    topic_name: "Personal Development",
    coverage: "full",
    source: makeCard().source,
    authors: ["Ada Example"],
    source_count: 1,
    part_count: 3,
    minutes: 2,
    published_at: "2026-10-14T00:00:00Z",
    ...overrides,
  };
}

function makeDetail(overrides: Partial<SummaryDetail> = {}): SummaryDetail {
  const parts = [1, 2, 3].map((n) => makeCard({ id: `example-book--0${n}`, title: `Idea ${n}` }));
  return { ...makeSummary(), parts, ...overrides };
}

afterEach(() => {
  window.localStorage.clear();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("summary helpers", () => {
  it("labels and describes summaries", () => {
    expect(coverageLabel({ coverage: "full" })).toBe("Full summary");
    expect(coverageLabel({ coverage: "key-ideas" })).toBe("Key ideas summary");
    expect(coverageLabel({ coverage: "topic" })).toBe("Topic summary");
    expect(coverageLabel({ coverage: "guide" })).toBe("Complete guide");
    expect(summaryByline({ kind: "book", authors: ["Robert Greene"], source_count: 1 })).toBe("by Robert Greene");
    expect(summaryByline({ kind: "topic", authors: ["Seneca", "NHS", "Montaigne", "Megan Devine"], source_count: 5 })).toBe(
      "From 5 sources, including Seneca, NHS and more",
    );
    expect(summaryMeta({ part_count: 30, minutes: 18 })).toBe("30 parts · 18 min");
    expect(summaryHref("a b", { part: 3, view: "all" })).toBe("/summaries/a%20b?view=all&part=3");
    expect(summaryHref("x", { part: 1 })).toBe("/summaries/x");
  });

  it("keeps a signed-out reader's place, and finishing sticks", () => {
    expect(localProgress("x")).toBeNull();
    saveLocalProgress("x", 4, false);
    expect(localProgress("x")).toEqual({ started: true, position: 4, finished: false });
    expect(resumeIndex(localProgress("x"), 10)).toBe(4);
    expect(resumeIndex(localProgress("x"), 3)).toBe(2);
    saveLocalProgress("x", 9, true);
    saveLocalProgress("x", 1, false);
    expect(localProgress("x")?.finished).toBe(true);
    // Finished: "Read again" starts from the beginning.
    expect(resumeIndex(localProgress("x"), 10)).toBe(0);
  });
});

describe("<SummaryPost>", () => {
  it("shows the cover, part count and the three ways in", () => {
    render(
      <AuthProvider>
        <SummaryPost summary={makeSummary({ coverage: "key-ideas" })} />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "An Example Book" })).toBeTruthy();
    expect(screen.getByText("Key ideas summary")).toBeTruthy();
    expect(screen.getByText("3 parts · 2 min")).toBeTruthy();
    expect(screen.getByRole("link", { name: /Start reading/ }).getAttribute("href")).toBe("/summaries/example-book");
    expect(screen.getByRole("link", { name: /Read it all/ }).getAttribute("href")).toBe("/summaries/example-book?view=all");
  });

  it("offers to continue where the reader stopped", () => {
    render(
      <AuthProvider>
        <SummaryPost summary={makeSummary({ viewer: { started: true, position: 1, finished: false } })} />
      </AuthProvider>,
    );
    expect(screen.getByRole("link", { name: /Continue/ }).getAttribute("href")).toBe("/summaries/example-book?part=2");
    expect(screen.getByText("Part 2 of 3")).toBeTruthy();
  });
});

describe("<Timeline> with summary posts", () => {
  it("shows summary posts between cards and leaves them out of Listen mode", () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(200, { posts: [], next_cursor: null })));
    const item: SummaryItem = { id: "summary:example-book", kind: "summary", summary: makeSummary() };
    const posts = [makePost(), item, makePost({ card: makeCard({ id: "example-book--02", title: "Idea 2" }) })];
    expect(cardPosts(posts).map((p) => p.id)).toEqual(["example-book--01", "example-book--02"]);
    render(
      <AuthProvider>
        <Timeline initialPosts={posts} initialCursor={null} />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "An Example Book" })).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Idea 2" })).toBeTruthy();
  });
});

describe("<SummaryReader>", () => {
  it("turns pages with the buttons, keys and swipes, then shows the finish", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(204, {})));
    render(
      <AuthProvider>
        <SummaryReader summary={makeDetail()} />
      </AuthProvider>,
    );
    expect(screen.getByRole("heading", { name: "Idea 1" })).toBeTruthy();
    expect(screen.getByText("Part 1 of 3", { selector: "span" })).toBeTruthy();
    expect((screen.getByRole("button", { name: /Previous/ }) as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(screen.getByRole("button", { name: /Next/ }));
    expect(screen.getByRole("heading", { name: "Idea 2" })).toBeTruthy();
    fireEvent.keyDown(window, { key: "ArrowLeft" });
    expect(screen.getByRole("heading", { name: "Idea 1" })).toBeTruthy();

    const part = screen.getByRole("region", { name: "Part 1 of 3" });
    fireEvent.touchStart(part, { touches: [{ clientX: 300, clientY: 100 }] });
    fireEvent.touchEnd(part, { changedTouches: [{ clientX: 100, clientY: 110 }] });
    expect(screen.getByRole("heading", { name: "Idea 2" })).toBeTruthy();

    fireEvent.keyDown(window, { key: "ArrowRight" });
    expect(screen.getByRole("button", { name: /Finish/ })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: /Finish/ }));
    expect(screen.getByText("You've finished An Example Book")).toBeTruthy();
    await waitFor(() => expect(localProgress("example-book")?.finished).toBe(true));
  });

  it("picks up a signed-out reader where they stopped", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(204, {})));
    saveLocalProgress("example-book", 1, false);
    render(
      <AuthProvider>
        <SummaryReader summary={makeDetail()} />
      </AuthProvider>,
    );
    expect(await screen.findByRole("heading", { name: "Idea 2" })).toBeTruthy();
    expect(screen.getByText(/Picking up where you left off, at part 2/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Start from the beginning" }));
    expect(screen.getByRole("heading", { name: "Idea 1" })).toBeTruthy();
  });

  it("resumes and saves a signed-in reader's place through the API", async () => {
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    const puts: unknown[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: string, init?: RequestInit) => {
        const url = String(input);
        if (url.endsWith("/v1/me")) return json(200, user);
        if (url.endsWith("/v1/summaries/example-book") && (!init?.method || init.method === "GET"))
          return json(200, makeDetail({ viewer: { started: true, position: 2, finished: false } }));
        if (url.endsWith("/progress")) {
          puts.push(JSON.parse(String(init?.body)));
          return json(200, { started: true, position: 0, finished: false });
        }
        return json(204, {});
      }),
    );
    render(
      <AuthProvider>
        <SummaryReader summary={makeDetail()} />
      </AuthProvider>,
    );
    expect(await screen.findByRole("heading", { name: "Idea 3" })).toBeTruthy();
    await waitFor(() => expect(puts).toContainEqual({ position: 2, finished: true }));
    fireEvent.click(screen.getByRole("button", { name: /Previous/ }));
    await waitFor(() => expect(puts).toContainEqual({ position: 1, finished: false }));
  });

  it("shows every part on one page with Read it all", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(204, {})));
    render(
      <AuthProvider>
        <SummaryReader summary={makeDetail()} initialView="all" />
      </AuthProvider>,
    );
    expect(screen.getAllByRole("heading", { level: 2 }).map((h) => h.textContent)).toEqual(["Idea 1", "Idea 2", "Idea 3"]);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "One at a time" }));
    });
    expect(screen.getAllByRole("heading", { level: 2 })).toHaveLength(1);
  });
});
