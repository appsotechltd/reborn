import type { NextConfig } from "next";

// Reborn uses the classic ISR caching model (route-level `revalidate` plus
// fetch-level `next.revalidate`) rather than Cache Components: public pages are
// rendered once per URL on first request and refreshed every 10 minutes, the
// first visit to an un-prebuilt URL blocks until real content is ready (good
// for crawlers and link previews), and unknown ids return a real 404.
const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  async headers() {
    return [
      // Only embeds (/embed/*) may be framed, by any site. Everything else is same-origin only.
      {
        source: "/((?!embed/).*)",
        headers: [
          { key: "X-Frame-Options", value: "SAMEORIGIN" },
          { key: "Content-Security-Policy", value: "frame-ancestors 'self'" },
        ],
      },
      {
        source: "/embed/:path*",
        headers: [{ key: "Content-Security-Policy", value: "frame-ancestors *" }],
      },
    ];
  },
};

export default nextConfig;
