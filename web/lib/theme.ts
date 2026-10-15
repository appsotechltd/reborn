/**
 * Light / dark mode. Dark is the default (as in the app). A reader can pick
 * Light, or System to follow the browser's prefers-color-scheme, in Settings
 * or with the header's sun/moon button; the choice is kept per browser in
 * localStorage and written to <html data-theme> by an inline script before
 * first paint. The server renders data-theme="dark".
 */

export type ThemeChoice = "system" | "light" | "dark";
export type Theme = "light" | "dark";

export const THEME_KEY = "reborn.theme";
export const THEME_CHOICES: readonly ThemeChoice[] = ["system", "light", "dark"];
/** What a reader who hasn't chosen gets. */
export const DEFAULT_THEME: ThemeChoice = "dark";
const DARK_QUERY = "(prefers-color-scheme: dark)";
const CHANGE_EVENT = "reborn:theme";

function isChoice(v: unknown): v is ThemeChoice {
  return v === "system" || v === "light" || v === "dark";
}

// Used when localStorage is blocked, so a choice still holds for this page view.
let memoryChoice: ThemeChoice = DEFAULT_THEME;

/** The stored choice, or the default (dark) when none is stored. */
export function readThemeChoice(): ThemeChoice {
  try {
    const v = window.localStorage.getItem(THEME_KEY);
    return isChoice(v) ? v : DEFAULT_THEME;
  } catch {
    return memoryChoice;
  }
}

/** Whether the browser currently prefers dark. */
export function prefersDark(): boolean {
  try {
    return typeof window.matchMedia === "function" && window.matchMedia(DARK_QUERY).matches;
  } catch {
    return false;
  }
}

/** The mode a choice resolves to right now. */
export function resolveTheme(choice: ThemeChoice, dark = prefersDark()): Theme {
  if (choice === "system") return dark ? "dark" : "light";
  return choice;
}

/** Applies a choice to <html>. "system" removes the attribute so the media query decides. */
export function applyTheme(choice: ThemeChoice, root: HTMLElement = document.documentElement) {
  if (choice === "system") root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", choice);
}

/** Stores, applies and announces a choice. */
export function setThemeChoice(choice: ThemeChoice) {
  memoryChoice = choice;
  try {
    // System is stored too: with nothing stored the site is dark.
    window.localStorage.setItem(THEME_KEY, choice);
  } catch {
    // Storage blocked (private mode, disabled site data): still apply for this page view.
  }
  applyTheme(choice);
  window.dispatchEvent(new CustomEvent(CHANGE_EVENT, { detail: choice }));
}

/**
 * Subscribes to anything that can change the effective theme: a choice made
 * in this tab, one made in another tab, or the OS switching modes.
 */
export function subscribeTheme(onChange: () => void): () => void {
  const onStorage = (e: StorageEvent) => {
    if (e.key === THEME_KEY || e.key === null) {
      applyTheme(readThemeChoice());
      onChange();
    }
  };
  window.addEventListener(CHANGE_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  let mq: MediaQueryList | null = null;
  try {
    mq = typeof window.matchMedia === "function" ? window.matchMedia(DARK_QUERY) : null;
    mq?.addEventListener?.("change", onChange);
  } catch {
    mq = null;
  }
  return () => {
    window.removeEventListener(CHANGE_EVENT, onChange);
    window.removeEventListener("storage", onStorage);
    mq?.removeEventListener?.("change", onChange);
  };
}

/**
 * Runs in <head> before the body is parsed, so the reader's choice is in place
 * before first paint (no flash of the wrong theme): Light or Dark pins it,
 * System hands it to the media query, and no choice keeps the default dark.
 */
export const themeScript = `(function(){var r=document.documentElement;try{var t=localStorage.getItem(${JSON.stringify(
  THEME_KEY,
)});if(t==="light"||t==="dark")r.setAttribute("data-theme",t);else if(t==="system")r.removeAttribute("data-theme");else r.setAttribute("data-theme","dark")}catch(e){r.setAttribute("data-theme","dark")}})()`;

/** The header's switch: pins the opposite of what is showing now. */
export function toggleTheme() {
  setThemeChoice(resolveTheme(readThemeChoice()) === "dark" ? "light" : "dark");
}
