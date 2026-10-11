"use client";

import { useLayoutEffect } from "react";
import { applyTheme, readThemeChoice } from "@/lib/theme";

/**
 * Re-applies the stored Light/Dark choice once React has mounted the page.
 *
 * The inline head script (themeScript) covers normal page loads before first paint.
 * It does not run on pages React renders on the client from scratch, such as the
 * 404 for an unknown idea, source, topic or author: there Next.js serves a bare error
 * shell, React rebuilds <html> without the attribute, and a script inserted by React
 * never executes. A layout effect still runs before the browser paints.
 */
export function ThemeSync() {
  useLayoutEffect(() => {
    applyTheme(readThemeChoice());
  }, []);
  return null;
}
