"use client";

import { useSyncExternalStore } from "react";
import {
  prefersDark,
  readThemeChoice,
  setThemeChoice,
  subscribeTheme,
  THEME_CHOICES,
  type ThemeChoice,
} from "@/lib/theme";

const LABELS: Record<ThemeChoice, string> = { system: "System", light: "Light", dark: "Dark" };

/** System / Light / Dark switch (dark by default). The choice is remembered in this browser only; the header's sun/moon button changes it too. */
export function ThemeSwitch() {
  const choice = useSyncExternalStore<ThemeChoice>(subscribeTheme, readThemeChoice, () => "dark");
  const systemDark = useSyncExternalStore(subscribeTheme, prefersDark, () => false);

  return (
    <fieldset>
      <legend className="label">Appearance</legend>
      <p className="hint mb-3 mt-0" id="theme-hint">
        Dark unless you pick otherwise. System follows your device&apos;s setting
        {choice === "system" ? ` (currently ${systemDark ? "dark" : "light"})` : ""}. Saved in this browser.
      </p>
      <div className="inline-flex rounded-full border border-line bg-surface p-1">
        {THEME_CHOICES.map((c) => (
          <label
            key={c}
            className="cursor-pointer rounded-full has-[:checked]:bg-chip-on has-[:checked]:text-chip-on-fg has-[:focus-visible]:outline has-[:focus-visible]:outline-3 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-accent-text"
          >
            <input
              type="radio"
              name="theme"
              value={c}
              className="sr-only"
              aria-describedby="theme-hint"
              checked={c === choice}
              onChange={() => setThemeChoice(c)}
            />
            <span
              className={`inline-flex min-h-9 items-center px-4 text-sm ${
                c === choice ? "font-semibold" : "font-medium text-muted hover:text-fg"
              }`}
            >
              {LABELS[c]}
            </span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}
