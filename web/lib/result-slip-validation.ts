import { createHash } from 'node:crypto'
import type { createAdminClient } from '@/lib/supabase/admin'

/** Reserve one of three durable slots before doing any Storage work. */
export async function claimResultSlipValidation(
  admin: Awaited<ReturnType<typeof createAdminClient>>,
  actorId: string,
  path: string,
) {
  const action = 'result_slip_validation'
  // Intents expire after 2h15m; retain slots well beyond that lifetime.
  const { error: cleanupError } = await admin.from('rate_limit_events').delete()
    .eq('actor_id', actorId).eq('action', action)
    .lt('created_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
  if (cleanupError) return false

  for (let attempt = 0; attempt < 3; attempt++) {
    // Deterministic UUIDs let the existing primary key serialize concurrent
    // callers across server instances. Only a successful INSERT spends a slot.
    const hash = createHash('sha256').update(JSON.stringify([action, actorId, path, attempt])).digest('hex')
    const id = `${hash.slice(0, 8)}-${hash.slice(8, 12)}-8${hash.slice(13, 16)}-a${hash.slice(17, 20)}-${hash.slice(20, 32)}`
    const { error } = await admin.from('rate_limit_events').insert({ id, actor_id: actorId, action })
    if (!error) return true
    if (error.code !== '23505') return false
  }
  return false
}
