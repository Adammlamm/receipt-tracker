import type { Metadata, Viewport } from "next";
import "./globals.css";
import PageTransition from "@/components/PageTransition";

export const metadata: Metadata = {
  title: "Receipt Tracker",
  description: "Split receipts and track who owes you.",
  manifest: "/manifest.json",
  icons: {
    icon: "/favicon.png",
    apple: "/icons/apple-touch-icon.png",
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Receipts",
  },
  openGraph: {
    title: "Receipt Tracker",
    description: "Split receipts and track who owes you.",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#1F7A5C",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="font-sans text-ink">
        <div className="max-w-md mx-auto min-h-screen pb-24 relative">
          <PageTransition>{children}</PageTransition>
        </div>
      </body>
    </html>
  );
}
