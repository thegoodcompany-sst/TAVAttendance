import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

type RpcClient = Pick<SupabaseClient, 'rpc'>

/**
 * Checks the single database-managed privileged principal installed by
 * migration 038. Keeping identity and role checks in PostgreSQL prevents an
 * application environment variable from drifting away from destructive RPC
 * authorization.
 */
export async function isSuperadmin(supabase: RpcClient): Promise<boolean> {
  const { data, error } = await supabase.rpc('is_superadmin')
  return !error && data === true
}
