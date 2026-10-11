import { act, fireEvent, render, screen, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CardsBrowser } from "@/components/CardsBrowser";
import { LibraryBrowser, LibraryHeader } from "@/components/Library";
import { ListenDock } from "@/components/ListenDock";
import { AuthProvider } from "@/lib/auth";
import { ListenProvider } from "@/lib/listen";
import { setListeningPlaying } from "@/lib/media-focus";
import type { AuthorSummary, Card } from "@/lib/types";
import { makeCard } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  usePathname: () => "/authors",
}));

const author = (name: string, extra: Partial<AuthorSummary> = {}): AuthorSummary => ({
  name,
  sources: 1,
  card_count: 10,
  video_count: 0,
  topics: ["personal-development"],
  followers: 0,
  ...extra,
});

const json = (body: unknown) => new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } });

function card(n: number, video = false): Card {
  const id = `example-book--0${n}`;
  return makeCard({
    id,
    title: `Idea ${n}`,
    audio: { url: `/audio/${id}.mp3`, duration_s: 40, voice: "bm_george", voice_name: "George" },
    explainer: video
      ? {
          kind: "animated",
          video_url: `/media/${id}.mp4`,
          poster_url: `/media/${id}.jpg`,
          duration_s: 50,
          width: 720,
          height: 1280,
          narrated: false,
        }
      : null,
  });
}

function App({ children }: { children: ReactNode }) {
  return (
    <AuthProvider>
      <ListenProvider>
        {children}
        <ListenDock />
      </ListenProvider>
    </AuthProvider>
  );
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
  setListeningPlaying(false);
});

describe("Library", () => {
  it("links the Books and Authors tabs, marking the current one", () => {
    render(<LibraryHeader current="authors" />);
    const tabs = screen.getByRole("navigation", { name: "Library" });
    expect(within(tabs).getByRole("link", { name: "Books" }).getAttribute("href")).toBe("/sources");
    const current = within(tabs).getByRole("link", { name: "Authors" });
    expect(current.getAttribute("href")).toBe("/authors");
    expect(current.getAttribute("aria-current")).toBe("page");
  });

  it("lists authors with their books, ideas and videos, and searches, filters and pages", async () => {
    vi.useFakeTimers();
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input));
      if (url.searchParams.get("cursor") === "2") return json({ authors: [author("Cy Third")], next_cursor: null });
      if (url.searchParams.get("topic") === "money") return json({ authors: [], next_cursor: null });
      if (url.searchParams.get("q") === "ep")
        return json({ authors: [author("Epictetus", { video_count: 1 })], next_cursor: null });
      return json({ authors: [], next_cursor: null });
    });
    vi.stubGlobal("fetch", fetchMock);

    render(
      <App>
        <LibraryBrowser
          kind="authors"
          initial={{
            items: [author("Ada Example", { sources: 2, card_count: 30, video_count: 3 }), author("Bo Second")],
            cursor: "2",
          }}
        />
      </App>,
    );

    const list = screen.getByRole("list", { name: "Authors" });
    const ada = within(list).getByRole("link", { name: "Ada Example" });
    expect(ada.getAttribute("href")).toBe("/authors/Ada%20Example");
    const adaRow = ada.closest("li")!;
    expect(within(adaRow).getByText("2 books")).toBeTruthy();
    expect(within(adaRow).getByText("30 ideas")).toBeTruthy();
    expect(within(adaRow).getByText("3 videos")).toBeTruthy();
    // No video badge when an author has none.
    const bo = within(list).getByRole("link", { name: "Bo Second" }).closest("li")!;
    expect(within(bo).queryByText(/video/)).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();

    // Next page.
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Load more authors" }));
    });
    expect(within(list).getByRole("link", { name: "Cy Third" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Load more authors" })).toBeNull();

    // Search waits for the reader to stop typing, then asks once.
    fireEvent.change(screen.getByLabelText("Search authors by name"), { target: { value: "e" } });
    fireEvent.change(screen.getByLabelText("Search authors by name"), { target: { value: "ep" } });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(300);
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1][0])).toContain("/v1/authors?q=ep&limit=50");
    const results = screen.getByRole("list", { name: "Authors" });
    expect(within(results).getAllByRole("listitem")).toHaveLength(1);
    expect(within(results).getByText("1 video")).toBeTruthy();
    expect(window.location.search).toBe("?q=ep");

    // A topic filters straight away, with the search kept.
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Money" }));
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(String(fetchMock.mock.calls[2][0])).toContain("q=ep&topic=money");
    expect(screen.getByRole("button", { name: "Money" }).getAttribute("aria-pressed")).toBe("true");
    expect(screen.getByText("No authors match. Try another word or topic.")).toBeTruthy();
    window.history.replaceState(null, "", "/");
  });
});

describe("A book's or an author's cards", () => {
  beforeEach(() => {
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
    vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
    vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
    vi.stubGlobal("fetch", vi.fn(async () => json({ posts: [], next_cursor: null })));
  });

  it("has no All / Videos switch when there are no videos", () => {
    render(
      <App>
        <CardsBrowser cards={[card(1), card(2)]} queue="source:example-book" listenLabel="Listen to this book" context="from this book" />
      </App>,
    );
    expect(screen.getByRole("heading", { name: "2 ideas from this book" })).toBeTruthy();
    expect(screen.queryByRole("group", { name: "Show" })).toBeNull();
  });

  it("switches between all cards and videos, with counts", () => {
    render(
      <App>
        <CardsBrowser
          cards={[card(1), card(2, true), card(3), card(4, true)]}
          queue="author:Ada Example"
          listenLabel="Listen to this author"
          context="by Ada Example"
        />
      </App>,
    );
    const all = screen.getByRole("button", { name: "All (4)" });
    const videos = screen.getByRole("button", { name: "Videos (2)" });
    expect(all.getAttribute("aria-pressed")).toBe("true");
    expect(screen.getAllByRole("link", { name: /^Idea / })).toHaveLength(4);

    fireEvent.click(videos);
    expect(videos.getAttribute("aria-pressed")).toBe("true");
    expect(screen.getByRole("heading", { name: "2 videos by Ada Example" })).toBeTruthy();
    expect(screen.getAllByRole("link", { name: /^Idea / }).map((l) => l.textContent)).toEqual(["Idea 2", "Idea 4"]);

    fireEvent.click(all);
    expect(screen.getAllByRole("link", { name: /^Idea / })).toHaveLength(4);
  });

  it("listens to the cards shown, in order, as their own queue", () => {
    render(
      <App>
        <CardsBrowser
          cards={[card(1), card(2, true), card(3), card(4, true)]}
          queue="source:example-book"
          listenLabel="Listen to this book"
          context="from this book"
        />
      </App>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Videos (2)" }));
    fireEvent.click(screen.getByRole("button", { name: "Listen to this book" }));
    expect(HTMLMediaElement.prototype.play).toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Pause", pressed: true })).toBeTruthy();

    const bar = screen.getByRole("region", { name: "Listen mode" });
    expect(within(bar).getByText("Idea 2")).toBeTruthy();
    fireEvent.click(within(bar).getByRole("button", { name: /Idea 2.*Open the player/ }));
    expect(within(screen.getByRole("dialog", { name: "Idea 2" })).getByText(/Idea 1 of 2/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Close the player" }));

    // Next goes to the next video, not the next card of the book.
    fireEvent.click(within(bar).getByRole("button", { name: "Next idea" }));
    expect(within(bar).getByText("Idea 4")).toBeTruthy();

    // Pausing from the page, then switching back to All offers a fresh start of every card.
    fireEvent.click(screen.getByRole("button", { name: "Pause", pressed: true }));
    expect(screen.getByRole("button", { name: "Resume", pressed: false })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "All (4)" }));
    fireEvent.click(screen.getByRole("button", { name: "Listen to this book" }));
    expect(within(bar).getByText("Idea 1")).toBeTruthy();
    // A fixed list: Listen mode never asks the timeline for more.
    expect(vi.mocked(fetch).mock.calls.some(([u]) => String(u).includes("/v1/timeline"))).toBe(false);
  });
});
