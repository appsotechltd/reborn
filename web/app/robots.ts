import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/config";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: [
        "/stashes",
        "/review",
        "/quiz",
        "/ask",
        "/contribute",
        "/moderation",
        "/settings",
        "/signin",
        "/register",
      ],
    },
    sitemap: `${siteUrl()}/sitemap.xml`,
  };
}
