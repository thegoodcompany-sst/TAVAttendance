import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { getDemoClient } from '@/lib/demo/state'

type CookieStore = Awaited<ReturnType<typeof cookies>>
type ServerClient = ReturnType<typeof createRealClient>

export async function createClient(): Promise<ServerClient> {
  // Demo mode (signed in as the demo email): every query is answered by the
  // in-memory demo emulator. It has no network access, so the real database is
  // never read or written. See lib/demo/.
  const demo = await getDemoClient()
  if (demo) return demo as unknown as ServerClient

  return createRealClient(await cookies())
}

function createRealClient(cookieStore: CookieStore) {
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // Server Component — cookie writes are handled by middleware
          }
        },
      },
    }
  )
}
