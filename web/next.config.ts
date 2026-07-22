import type { NextConfig } from "next";
import path from "path";

// NOTE: The CSP here uses 'unsafe-inline' for scripts and styles to avoid
// breaking Next.js inline runtime scripts and style injection. Consider
// tightening this with nonces (next/headers + generateBuildId) in a future
// hardening pass once the app stabilises.
//
// Supabase origins are read from the environment at build time. When the
// variable is absent, the policy fails closed rather than trusting every
// project on the shared supabase.co domain.
const configuredSupabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL)
  : null
const supabaseOrigin = configuredSupabaseUrl?.origin
const supabaseWebsocketOrigin = configuredSupabaseUrl
  ? `${configuredSupabaseUrl.protocol === 'https:' ? 'wss:' : 'ws:'}//${configuredSupabaseUrl.host}`
  : null

function sources(...values: Array<string | null | undefined>) {
  return values.filter((value): value is string => Boolean(value)).join(' ')
}

const cspDirectives = [
  `default-src 'self'`,
  `script-src 'self' 'unsafe-inline'`,
  `style-src 'self' 'unsafe-inline'`,
  `img-src ${sources("'self'", 'data:', 'blob:', supabaseOrigin)}`,
  `font-src 'self'`,
  `connect-src ${sources("'self'", supabaseOrigin, supabaseWebsocketOrigin)}`,
  `frame-src 'none'`,
  `frame-ancestors 'none'`,
  `object-src 'none'`,
  `base-uri 'self'`,
  `form-action 'self'`,
].join('; ')

const securityHeaders = [
  { key: 'Strict-Transport-Security', value: 'max-age=63072000' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-DNS-Prefetch-Control', value: 'off' },
  { key: 'X-Permitted-Cross-Domain-Policies', value: 'none' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
  { key: 'Cross-Origin-Opener-Policy', value: 'same-origin' },
  { key: 'Content-Security-Policy', value: cspDirectives },
]

const nextConfig: NextConfig = {
  poweredByHeader: false,
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
