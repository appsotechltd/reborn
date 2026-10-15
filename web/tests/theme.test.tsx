import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ThemeSwitch } from "@/components/ThemeSwitch";
import { ThemeToggle } from "@/components/ThemeToggle";
import { readThemeChoice, resolveTheme, setThemeChoice, THEME_KEY, themeScript } from "@/lib/theme";

/** A controllable prefers-color-scheme media query. */
function mockMedia(initialDark: boolean) {
  let dark = initialDark;
  const listeners = new Set<(e: MediaQueryListEvent) => void>();
  window.matchMedia = vi.fn((query: string) => ({
    get matches() {
      return query.includes("dark") ? dark : !dark;
    },
    media: query,
    onchange: null,
    addEventListener: (_: string, l: (e: MediaQueryListEvent) => void) => listeners.add(l),
    removeEventListener: (_: string, l: (e: MediaQueryListEvent) => void) => listeners.delete(l),
    addListener: () => {},
    removeListener: () => {},
    dispatchEvent: () => true,
  })) as unknown as typeof window.matchMedia;
  return {
    set(next: boolean) {
      dark = next;
      listeners.forEach((l) => l({ matches: next } as MediaQueryListEvent));
    },
  };
}

const html = document.documentElement;
const radio = (name: string) => screen.getByRole("radio", { name }) as HTMLInputElement;

beforeEach(() => {
  setThemeChoice("dark"); // also resets the in-memory fallback to the default
  localStorage.clear();
  html.removeAttribute("data-theme");
});
afterEach(() => {
  vi.restoreAllMocks();
});

describe("theme", () => {
  it("applies the stored choice before paint (inline head script)", () => {
    localStorage.setItem(THEME_KEY, "dark");
    new Function(themeScript)();
    expect(html.getAttribute("data-theme")).toBe("dark");

    localStorage.setItem(THEME_KEY, "light");
    new Function(themeScript)();
    expect(html.getAttribute("data-theme")).toBe("light");

    localStorage.setItem(THEME_KEY, "system");
    new Function(themeScript)();
    expect(html.hasAttribute("data-theme")).toBe(false);

    // No choice (or a broken one): dark, the default.
    localStorage.removeItem(THEME_KEY);
    new Function(themeScript)();
    expect(html.getAttribute("data-theme")).toBe("dark");
    localStorage.setItem(THEME_KEY, "nonsense");
    html.removeAttribute("data-theme");
    new Function(themeScript)();
    expect(html.getAttribute("data-theme")).toBe("dark");
  });

  it("is dark by default, even when the device prefers light", () => {
    mockMedia(false);
    expect(readThemeChoice()).toBe("dark");
    render(<ThemeSwitch />);
    expect(radio("Dark").checked).toBe(true);
  });

  it("the header button flips the mode and Settings follows", () => {
    mockMedia(false);
    html.setAttribute("data-theme", "dark");
    render(
      <>
        <ThemeToggle />
        <ThemeSwitch />
      </>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Switch to light mode" }));
    expect(html.getAttribute("data-theme")).toBe("light");
    expect(localStorage.getItem(THEME_KEY)).toBe("light");
    expect(radio("Light").checked).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Switch to dark mode" }));
    expect(html.getAttribute("data-theme")).toBe("dark");
    expect(radio("Dark").checked).toBe(true);
  });

  it("from System, the header button pins the opposite of what is showing", () => {
    mockMedia(true);
    localStorage.setItem(THEME_KEY, "system");
    render(<ThemeToggle />);
    fireEvent.click(screen.getByRole("button", { name: "Switch to light mode" }));
    expect(localStorage.getItem(THEME_KEY)).toBe("light");
  });

  it("shows the stored choice in Settings and stores a new one", () => {
    mockMedia(false);
    localStorage.setItem(THEME_KEY, "light");
    render(<ThemeSwitch />);
    expect(radio("Light").checked).toBe(true);

    fireEvent.click(radio("Dark"));
    expect(radio("Dark").checked).toBe(true);
    expect(localStorage.getItem(THEME_KEY)).toBe("dark");
    expect(html.getAttribute("data-theme")).toBe("dark");
  });

  it("System is stored and follows the media query", () => {
    const media = mockMedia(true);
    localStorage.setItem(THEME_KEY, "light");
    html.setAttribute("data-theme", "light");
    render(<ThemeSwitch />);

    fireEvent.click(radio("System"));
    expect(localStorage.getItem(THEME_KEY)).toBe("system");
    expect(html.hasAttribute("data-theme")).toBe(false); // CSS media query decides
    expect(resolveTheme("system")).toBe("dark");
    expect(screen.getByText(/currently dark/)).toBeTruthy();

    act(() => media.set(false));
    expect(resolveTheme("system")).toBe("light");
    expect(screen.getByText(/currently light/)).toBeTruthy();
  });

  it("falls back to dark when storage is unavailable", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(readThemeChoice()).toBe("dark");
    expect(() => new Function(themeScript)()).not.toThrow();
    expect(html.getAttribute("data-theme")).toBe("dark");
    mockMedia(false);
    render(<ThemeSwitch />);
    expect(radio("Dark").checked).toBe(true);
    fireEvent.click(radio("Light"));
    expect(html.getAttribute("data-theme")).toBe("light"); // still applied for this page view
    expect(radio("Light").checked).toBe(true);
  });
});
