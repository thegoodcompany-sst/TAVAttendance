import 'server-only'
import { createClient as createSupabaseClient, type SupabaseClient } from '@supabase/supabase-js'
import { getDemoClient } from '@/lib/demo/state'

export async function createAdminClient() {
  // Demo mode never gets the service-role client; it gets the same in-memory
  // demo database as createClient().
  const demo = await getDemoClient()
  if (demo) return demo as unknown as SupabaseClient

  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )
}
