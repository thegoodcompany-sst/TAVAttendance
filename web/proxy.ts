import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function proxy(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // getClaims() verifies the JWT locally against the project's asymmetric
  // signing key (cached JWKS) — no network round-trip to the Auth server on
  // every navigation, unlike getUser(). It still calls getSession() under the
  // hood, so an expired access token is refreshed and the new cookies written
  // via setAll above. This is only a coarse "is there a valid session" redirect
  // gate: a locally-verified JWT stays valid until it expires, so it won't catch
  // a session revoked server-side (ban / password change). The revocation-aware
  // authorization gate (full getUser() + role check) lives in the (admin) layout,
  // which runs once per layout render.
  const { data } = await supabase.auth.getClaims()
  const user = data?.claims ?? null
  const { pathname } = request.nextUrl

  // Auth-flow routes manage their own session client-side (invite/recovery
  // links deliver the session in the URL fragment, which the server can't see).
  // They must stay reachable without a server-visible session, and they show
  // their own error state if no valid token is present.
  const isAuthFlow =
    pathname === '/login' ||
    pathname === '/set-password' ||
    pathname === '/privacy' ||
    pathname.startsWith('/auth/')

  if (!user && !isAuthFlow) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // An already-signed-in admin hitting /login goes to the dashboard. Other
  // auth-flow routes (set-password, /auth/*) are left alone so invited users
  // can finish setting their password.
  if (user && pathname === '/login') {
    // getClaims() passes on a locally-valid JWT even after the session was
    // revoked server-side; the (admin) layout's getUser() then bounces back
    // to /login → infinite redirect loop (ERR_TOO_MANY_REDIRECTS). /login is
    // rare, so confirm with the Auth server before leaving it, and clear the
    // dead session cookies so the login form renders.
    const { data: verified } = await supabase.auth.getUser()
    if (verified.user) {
      return NextResponse.redirect(new URL('/', request.url))
    }
    await supabase.auth.signOut()
    return supabaseResponse
  }

  return supabaseResponse
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|altstore.json|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
