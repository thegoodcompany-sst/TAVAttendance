import { ensureDemoDatabase } from "@/lib/db";
import type { Metadata } from "next";
import { s } from "@/lib/strings";
import "./globals.css";
export const metadata: Metadata = {
  title: s.title,
  robots: { index: false, follow: false },
};
export const dynamic = "force-dynamic";
export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  await ensureDemoDatabase();
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html:
              "try{const t=localStorage.getItem('tp-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch{}",
          }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
