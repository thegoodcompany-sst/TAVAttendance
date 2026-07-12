'use server'

import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'

export async function wipeOperationalData(
  confirmation: string
): Promise<{ counts: Record<string, number> | null; error: string | null }> {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { counts: null, error: 'Not authenticated.' }
  if (!isSuperadmin(user)) return { counts: null, error: 'Not authorized.' }

  const { data, error } = await supabase.rpc('wipe_operational_data', { confirmation })
  if (error) return { counts: null, error: error.message }

  return { counts: (data ?? {}) as Record<string, number>, error: null }
}
