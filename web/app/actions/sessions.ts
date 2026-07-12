'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin, NRIC_RE } from '@/lib/admin'

export async function updateSessionNote(
  sessionId: string,
  notes: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const trimmed = notes.trim()
  if (NRIC_RE.test(trimmed)) {
    return { error: 'Notes must not contain an NRIC/FIN.' }
  }

  const { error } = await supabase
    .from('sessions')
    .update({ notes: trimmed || null })
    .eq('id', sessionId)
  if (error) return { error: error.message }

  revalidatePath('/')
  return { error: null }
}
