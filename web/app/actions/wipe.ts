'use server'

import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/admin'
import {
  acknowledgeAllStudentStorageCleanup,
  clearPrivateStudentBuckets,
} from '@/lib/storage-cleanup'
import { isSuperadmin } from '@/lib/superadmin'

export async function wipeOperationalData(
  confirmation: string
): Promise<{ counts: Record<string, number> | null; error: string | null }> {
  const { error: authError, supabase, user } = await requireAdmin()
  if (authError || !user) return { counts: null, error: authError ?? 'Not authenticated.' }
  if (!(await isSuperadmin(supabase))) return { counts: null, error: 'Not authorized.' }

  // The destructive RPC is service-role-only so even the principal cannot
  // bypass this Storage-aware orchestration through direct PostgREST calls.
  const { data, error } = await createAdminClient().rpc('wipe_operational_data_secure', {
    confirmation,
    p_actor_id: user.id,
  })
  if (error) return { counts: null, error: error.message }

  const counts = (data ?? {}) as Record<string, number>
  try {
    const adminClient = createAdminClient()
    await clearPrivateStudentBuckets(adminClient)
    await acknowledgeAllStudentStorageCleanup(adminClient)
  } catch (storageError) {
    const detail = storageError instanceof Error ? storageError.message : 'Unknown Storage error.'
    return {
      counts,
      error: `Database wipe completed, but private Storage cleanup failed: ${detail}`,
    }
  }

  return { counts, error: null }
}
