import type { Metadata } from "next";
import { Elms_Sans, Geist_Mono } from "next/font/google";
import "./globals.css";

// Mockup face (docs/drafts/web-dashboard-ui.html) — single family for UI + display.
const elmsSans = Elms_Sans({
  variable: "--font-sans",
  subsets: ["latin"],
  // Variable font; expose full weight range so font-medium/semibold/bold map cleanly.
  weight: "variable",
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "TAVA Attendance",
  description: "Admin dashboard for TAVA study centre attendance",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${elmsSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col font-sans">{children}</body>
    </html>
  );
}
