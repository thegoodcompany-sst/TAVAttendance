import type { Metadata } from "next";
import { Lato, Fredoka, Geist_Mono } from "next/font/google";
import "./globals.css";

// Body / UI face — exact match to the tava.sg marketing site.
const lato = Lato({
  variable: "--font-sans",
  subsets: ["latin"],
  weight: ["400", "700", "900"],
});

// Display face — bubbly, rounded; closest legible match to TAVA's hand-drawn
// marker headers. Used only on titles, headers, and the wordmark.
const fredoka = Fredoka({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
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
      className={`${lato.variable} ${fredoka.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
