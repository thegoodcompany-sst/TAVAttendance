import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  turbopack: {
    root: path.resolve(__dirname),
  },
  experimental: {
    // Keep visited admin pages in the client Router Cache so navigating
    // between them (and back) is instant and served from memory instead of
    // a fresh server round-trip. These pages read auth cookies so they're
    // per-user dynamic and can't be statically cached; this is the in-memory
    // lever. The 30s window is covered by each page's <AutoRefresh> so data
    // never drifts far. `static` lifts prefetched/loading shells to 3 min.
    staleTimes: {
      dynamic: 30,
      static: 180,
    },
  },
};

export default nextConfig;
