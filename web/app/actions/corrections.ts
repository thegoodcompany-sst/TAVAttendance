'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'

/**
 * Apply a correction request (PDPA s22): writes the requested value onto the
 * student, marks the request `applied`, and logs a `correction_response`
 * disclosure.
 */
export async function applyCorrection(requestId: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { data: studentId, error } = await supabase.rpc('review_correction_request', {
    p_request_id: requestId,
    p_decision: 'applied',
    p_review_note: null,
  })
  if (error) return { error: error.message }

  revalidatePath('/corrections')
  if (studentId) revalidatePath(`/students/${studentId}`)
  return { error: null }
}

/**
 * Reject a correction request (PDPA s22): marks it `rejected` with a note.
 */
export async function rejectCorrection(
  requestId: string,
  reviewNote: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase.rpc('review_correction_request', {
    p_request_id: requestId,
    p_decision: 'rejected',
    p_review_note: reviewNote.trim() || null,
  })

  if (error) return { error: error.message }

  revalidatePath('/corrections')
  return { error: null }
}
