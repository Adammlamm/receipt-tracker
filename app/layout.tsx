import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Receipt Tracker",
  description: "Split receipts and track who owes you.",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Receipts",
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
        <div className="max-w-md mx-auto min-h-screen pb-24 relative">{children}</div>
      </body>
    </html>
  );
}
