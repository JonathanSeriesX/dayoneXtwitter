import "./globals.css";

import type { Metadata, Viewport } from "next";
import { Montserrat } from "next/font/google";
import { ThemeProvider } from "next-themes";

import { LiquidPointer } from "./liquid-pointer";

const bodyFont = Montserrat({
  subsets: ["latin"],
  variable: "--font-body",
  display: "swap",
});

const url = "https://twixodus.evgenii.org";
const description =
  "The ultimate tool to seamlessly import your Twitter archive into the Day One journaling app.";

export const metadata: Metadata = {
  metadataBase: new URL(url),
  title: "Twixodus",
  description,
  robots: { index: true, follow: true },
  openGraph: {
    title: "Twixodus",
    description,
    siteName: "twixodus",
    locale: "en_GB",
    type: "website",
    url,
    images: [
      { url: "/pics/twatter.jpg", width: 637, height: 637, alt: "Twixodus" },
    ],
  },
  twitter: {
    card: "summary",
    creator: "@JonathanSeriesX",
    images: ["/pics/twatter.jpg"],
  },
};

export const viewport: Viewport = {
  /** browser chrome colour — keep in step with --paper in globals.css */
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f7f4ef" },
    { media: "(prefers-color-scheme: dark)", color: "#131110" },
  ],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    // suppressHydrationWarning: theme class is set pre-hydration by next-themes
    <html lang="en" className={bodyFont.variable} suppressHydrationWarning>
      <body className="font-sans antialiased">
        <ThemeProvider
          attribute="class"
          themes={["light", "dark", "black"]}
          enableColorScheme={false}
        >
          <div className="grain" aria-hidden />
          <LiquidPointer />
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
