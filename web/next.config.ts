import type { NextConfig } from "next";
import path from "path";

// NOTE: The CSP here uses 'unsafe-inline' for scripts and styles to avoid
// breaking Next.js inline runtime scripts and style injection. Consider
// tightening this with nonces (next/headers + generateBuildId) in a future
// hardening pass once the app stabilises.
//
// Supabase origin is read from the env var at build time; the wildcard
// *.supabase.co covers the project API, Auth, Realtime, and Storage endpoints.
const supabaseOrigin = process.env.NEXT_PUBLIC_SUPABASE_URL
  ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).origin
  : 'https://*.supabase.co'

const cspDirectives = [
  `default-src 'self'`,
  `script-src 'self' 'unsafe-inline'`,
  `style-src 'self' 'unsafe-inline'`,
  `img-src 'self' data: blob: https://*.supabase.co`,
  `font-src 'self'`,
  `connect-src 'self' ${supabaseOrigin} https://*.supabase.co wss://*.supabase.co`,
  `frame-ancestors 'none'`,
  `object-src 'none'`,
  `base-uri 'self'`,
  `form-action 'self'`,
].join('; ')

const securityHeaders = [
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Content-Security-Policy', value: cspDirectives },
]

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
  async headers() {
    return [
      {
        source: '/:path*',
        headers: securityHeaders,
      },
    ]
  },
};

export default nextConfig;
