"use client";

import { useSyncExternalStore } from "react";
import { prefersDark, readThemeChoice, resolveTheme, subscribeTheme, toggleTheme, type Theme } from "@/lib/theme";
import { Icon } from "./Icon";

function showing(): Theme {
  return resolveTheme(readThemeChoice(), prefersDark());
}

/**
 * The header's light/dark switch, as in the app: a sun while dark (switch to light), a moon while
 * light. It pins the other mode, the same choice as Appearance in Settings.
 */
export function ThemeToggle() {
  const theme = useSyncExternalStore<Theme>(subscribeTheme, showing, () => "dark");
  const dark = theme === "dark";
  const label = dark ? "Switch to light mode" : "Switch to dark mode";
  return (
    <button
      type="button"
      onClick={toggleTheme}
      aria-label={label}
      title={label}
      data-testid="theme-toggle"
      className="grid size-11 place-items-center rounded-full text-muted hover:bg-surface-2 hover:text-fg"
    >
      <Icon name={dark ? "sun" : "moon"} className="size-[1.375rem]" />
    </button>
  );
}
