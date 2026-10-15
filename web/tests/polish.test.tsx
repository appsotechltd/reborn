import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { BookCover, PostCover } from "@/components/Polish";
import { StreakChip } from "@/components/StreakChip";
import { AuthProvider } from "@/lib/auth";
import { coverColorsFor, firstSentence, personInitials, titleInitial } from "@/lib/polish";
import { makeCard } from "./fixtures";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
}));

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

describe("polish helpers (same as the app's)", () => {
  it("picks the same cover colours for the same id", () => {
    expect(coverColorsFor("meditations")).toEqual(coverColorsFor("meditations"));
    expect(coverColorsFor("a")).toEqual(["#3E4A5A", "#1D242E"]); // 97 % 8 = 1, as in the app
  });

  it("takes the title's initial, skipping The, A and An", () => {
    expect(titleInitial("The Art of War")).toBe("A");
    expect(titleInitial("an essay")).toBe("E");
    expect(titleInitial("Meditations")).toBe("M");
    expect(titleInitial("The")).toBe("T");
  });

  it("makes initials from first and last names", () => {
    expect(personInitials("Marcus Aurelius")).toBe("MA");
    expect(personInitials("Seneca")).toBe("S");
    expect(personInitials("Benjamin  Franklin Jr")).toBe("BJ");
  });

  it("cuts a quote to its first sentence for the cover", () => {
    expect(firstSentence("“We suffer more often in imagination than in reality. That is all.”")).toBe(
      "We suffer more often in imagination than in reality.",
    );
    expect(firstSentence("x".repeat(200))).toHaveLength(138);
  });
});

describe("<PostCover> and <BookCover>", () => {
  it("shows the quote's first sentence and the topic on a card with no picture", () => {
    const { container } = render(<PostCover card={makeCard({ quote: "Small steps add up over a lifetime. Always." })} topic="Habits" />);
    expect(container.textContent).toContain("Small steps add up over a lifetime.");
    expect(container.textContent).not.toContain("Always");
    expect(container.textContent).toContain("Habits");
    expect(container.querySelector("img")).toBeNull();
  });

  it("shows the card's picture when it has one", () => {
    const image = { url: "/media/images/x.png", caption: "A lamp", type: "illustration" } as never;
    render(<PostCover card={makeCard({ image })} topic="Habits" />);
    expect(screen.getByRole("img", { name: "A lamp" })).toBeTruthy();
  });

  it("draws a typeset book cover with the initial", () => {
    const { container } = render(<BookCover id="art-of-war" title="The Art of War" />);
    const cover = container.querySelector<HTMLElement>("[data-book-cover]")!;
    expect(cover.textContent).toBe("A");
    expect(cover.getAttribute("aria-hidden")).toBe("true");
    expect(cover.style.background).toContain("linear-gradient");
  });
});

describe("<StreakChip>", () => {
  afterEach(() => {
    window.localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("is hidden signed out", () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(200, {})));
    const { container } = render(
      <AuthProvider>
        <StreakChip />
      </AuthProvider>,
    );
    expect(container.textContent).toBe("");
  });

  it("shows the streak and opens today's idea and the streak in a sheet", async () => {
    const user = { id: "u1", email: "a@example.org", handle: "ada", display_name: "Ada", role: "member", topics: [] };
    window.localStorage.setItem("reborn.auth", JSON.stringify({ token: "tok", user }));
    const streak = { current: 4, longest: 9, goal: 3, today: 1, goal_met: false, last_days: [] };
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        const u = String(url);
        if (u.endsWith("/v1/me")) return json(200, user);
        if (u.endsWith("/v1/me/streak")) return json(200, streak);
        if (u.endsWith("/v1/daily")) return json(200, { date: "2026-10-15", card: makeCard({ title: "Daily one" }) });
        return json(200, {});
      }),
    );
    render(
      <AuthProvider>
        <StreakChip />
      </AuthProvider>,
    );
    const chip = await screen.findByRole("button", { name: /^4 day streak/ });
    expect(chip.textContent).toBe("4");
    fireEvent.click(chip);
    const sheet = screen.getByRole("dialog", { name: "Today" });
    expect(await within(sheet).findByTestId("daily-banner")).toBeTruthy();
    await waitFor(() => expect(within(sheet).getByRole("region", { name: "Your reading streak" })).toBeTruthy());
  });
});
