'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin, NRIC_RE } from '@/lib/admin'
import { isFeatureEnabled } from '@/lib/feature-flags'

export async function updateSessionNote(
  sessionId: string,
  notes: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }
  if (!(await isFeatureEnabled('session_notes'))) {
    return { error: 'Session notes are not enabled.' }
  }

  const trimmed = notes.trim()
  if (NRIC_RE.test(trimmed)) {
    return { error: 'Notes must not contain an NRIC/FIN.' }
  }

  const { error } = await supabase.rpc('update_session_note', {
    p_session_id: sessionId,
    p_notes: trimmed || null,
  })
  if (error) return { error: error.message }

  revalidatePath('/')
  return { error: null }
}
