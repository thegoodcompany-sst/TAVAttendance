import type { NextConfig } from "next";
import { fileURLToPath } from "node:url";
const config: NextConfig = {
  turbopack: { root: fileURLToPath(new URL("../../", import.meta.url)) },
  outputFileTracingRoot: fileURLToPath(new URL("../../", import.meta.url)),
  devIndicators: false,
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "Cache-Control", value: "no-store" },
          { key: "X-Content-Type-Options", value: "nosniff" },
        ],
      },
    ];
  },
};
export default config;
