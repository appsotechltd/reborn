import type { Metadata, Viewport } from "next";
import { SiteChrome } from "@/components/SiteChrome";
import { SiteFooter, SiteHeader } from "@/components/SiteHeader";
import { AuthProvider } from "@/lib/auth";
import { SiteUrlProvider } from "@/lib/site-url";
import { SITE_NAME, SITE_TAGLINE, siteUrl } from "@/lib/config";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl()),
  title: { default: `${SITE_NAME}: ${SITE_TAGLINE}`, template: `%s · ${SITE_NAME}` },
  description:
    "Reborn turns ideas from books and open sources into one-minute idea cards you can read, apply, review and quiz yourself on.",
  applicationName: SITE_NAME,
  openGraph: { siteName: SITE_NAME, type: "website", locale: "en" },
  twitter: { card: "summary" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#faf8f4" },
    { media: "(prefers-color-scheme: dark)", color: "#141311" },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="flex min-h-dvh flex-col antialiased">
        <SiteUrlProvider url={siteUrl()}>
          <AuthProvider>
            <SiteChrome header={<SiteHeader />} footer={<SiteFooter />}>
              {children}
            </SiteChrome>
          </AuthProvider>
        </SiteUrlProvider>
      </body>
    </html>
  );
}
