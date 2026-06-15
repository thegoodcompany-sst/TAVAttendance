'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

const NRIC_RE = /\b[STFGM][0-9]{7}[A-Z]\b/i

// Columns on `students` an admin is allowed to correct via this queue.
const CORRECTABLE_FIELDS = new Set([
  'full_name',
  'date_of_birth',
  'school',
  'year_of_study',
  'notes',
])

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' as const, supabase, user: null }

  const { data: profile } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') {
    return { error: 'Only admins can perform this action.' as const, supabase, user: null }
  }
  return { error: null, supabase, user }
}

/**
 * Apply a correction request (PDPA s22): writes the requested value onto the
 * student, marks the request `applied`, and logs a `correction_response`
 * disclosure.
 */
export async function applyCorrection(requestId: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { data: req, error: fetchErr } = await supabase
    .from('correction_requests')
    .select('id, student_id, field_name, requested_value, status')
    .eq('id', requestId)
    .single()

  if (fetchErr) return { error: fetchErr.message }
  if (req.status !== 'pending') return { error: 'This request has already been reviewed.' }
  if (!CORRECTABLE_FIELDS.has(req.field_name)) {
    return { error: `Field "${req.field_name}" cannot be corrected automatically.` }
  }
  if (req.field_name === 'notes' && req.requested_value && NRIC_RE.test(req.requested_value)) {
    return { error: 'Requested value appears to contain an NRIC/FIN and was rejected (PDPA).' }
  }

  const { error: updateErr } = await supabase
    .from('students')
    .update({ [req.field_name]: req.requested_value })
    .eq('id', req.student_id)
  if (updateErr) return { error: updateErr.message }

  const { error: markErr } = await supabase
    .from('correction_requests')
    .update({
      status: 'applied',
      reviewed_by: user!.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', requestId)
  if (markErr) return { error: markErr.message }

  const { error: discErr } = await supabase.from('data_disclosures').insert({
    student_id: req.student_id,
    disclosure_type: 'correction_response',
    disclosed_by: user!.id,
    detail: {
      request_id: requestId,
      field: req.field_name,
      applied_value: req.requested_value,
    },
  })
  if (discErr) return { error: `Correction applied but disclosure log failed: ${discErr.message}` }

  revalidatePath('/corrections')
  revalidatePath(`/students/${req.student_id}`)
  return { error: null }
}

/**
 * Reject a correction request (PDPA s22): marks it `rejected` with a note.
 */
export async function rejectCorrection(
  requestId: string,
  reviewNote: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase
    .from('correction_requests')
    .update({
      status: 'rejected',
      reviewed_by: user!.id,
      reviewed_at: new Date().toISOString(),
      review_note: reviewNote.trim() || null,
    })
    .eq('id', requestId)
    .eq('status', 'pending')

  if (error) return { error: error.message }

  revalidatePath('/corrections')
  return { error: null }
}
