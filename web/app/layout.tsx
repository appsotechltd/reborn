import type { Metadata, Viewport } from "next";
import { Figtree, Fraunces } from "next/font/google";
import { SiteChrome } from "@/components/SiteChrome";
import { SiteFooter, SiteHeader } from "@/components/SiteHeader";
import { AuthProvider } from "@/lib/auth";
import { ListenProvider } from "@/lib/listen";
import { ThemeSync } from "@/components/ThemeSync";
import { SiteUrlProvider } from "@/lib/site-url";
import { SITE_NAME, SITE_TAGLINE, siteUrl } from "@/lib/config";
import { themeScript } from "@/lib/theme";
import "./globals.css";

// Candlelight type: Fraunces 600 for titles, the wordmark and quotes; Figtree for reading text and UI.
const fraunces = Fraunces({
  subsets: ["latin"],
  weight: "600",
  style: ["normal", "italic"],
  variable: "--font-fraunces",
  display: "swap",
});
const figtree = Figtree({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-figtree",
  display: "swap",
});

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
  // Lets the phone tab bar pad itself clear of the home indicator (env(safe-area-inset-bottom)).
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#faf8f4" },
    { media: "(prefers-color-scheme: dark)", color: "#14110e" },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    // suppressHydrationWarning: the inline script may set data-theme before React hydrates.
    <html lang="en" className={`${fraunces.variable} ${figtree.variable}`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className="flex min-h-dvh flex-col antialiased">
        <ThemeSync />
        <SiteUrlProvider url={siteUrl()}>
          <AuthProvider>
            {/* Listen mode's player lives here, above the pages, so it keeps playing across navigation. */}
            <ListenProvider>
              <SiteChrome header={<SiteHeader />} footer={<SiteFooter />}>
                {children}
              </SiteChrome>
            </ListenProvider>
          </AuthProvider>
        </SiteUrlProvider>
      </body>
    </html>
  );
}
