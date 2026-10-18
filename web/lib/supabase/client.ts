import { createBrowserClient } from '@supabase/ssr'
import { DEMO_COOKIE } from '@/lib/demo/constants'
import { createDemoBrowserClient } from '@/lib/demo/browser-client'

/** True when this browser is signed in to the on-device demo. */
export function isDemoBrowser(): boolean {
  if (typeof document === 'undefined') return false
  return document.cookie.split(';').some(part => part.trim().startsWith(`${DEMO_COOKIE}=`))
}

export function createClient() {
  // Demo mode: a stub with no network access (see lib/demo/browser-client.ts).
  if (isDemoBrowser()) return createDemoBrowserClient() as unknown as ReturnType<typeof createBrowserClient>
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
