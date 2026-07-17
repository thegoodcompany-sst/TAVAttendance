'use server'

import { revalidatePath } from 'next/cache'
import { createAdminClient } from '@/lib/supabase/admin'
import { createClient } from '@/lib/supabase/server'

const ALLOWED_TYPES = new Set(['application/pdf', 'image/jpeg', 'image/png'])
const MAX_BYTES = 10 * 1024 * 1024

export async function uploadResultSlip(
  studentId: string,
  formData: FormData,
): Promise<{ error: string | null }> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const file = formData.get('file') as File | null
  const examName = (formData.get('exam_name') as string | null)?.trim()
  const subject = (formData.get('subject') as string | null)?.trim() || null
  const scoreRaw = (formData.get('score') as string | null)?.trim()
  const maxScoreRaw = (formData.get('max_score') as string | null)?.trim()
  const score = scoreRaw ? Number(scoreRaw) : null
  const maxScore = maxScoreRaw ? Number(maxScoreRaw) : null

  if (!examName) return { error: 'Exam name is required.' }
  if (!file || file.size === 0) return { error: 'A file is required.' }
  if (!ALLOWED_TYPES.has(file.type)) return { error: 'File must be a PDF, JPG, or PNG.' }
  if (file.size > MAX_BYTES) return { error: 'File must be under 10MB.' }
  if (score !== null && (!Number.isFinite(score) || score < 0)) return { error: 'Score must be zero or greater.' }
  if (maxScore !== null && (!Number.isFinite(maxScore) || maxScore <= 0)) return { error: 'Maximum score must be greater than zero.' }
  if (score !== null && maxScore !== null && score > maxScore) return { error: 'Score cannot exceed the maximum.' }

  // First folder segment must equal the student_id for the storage RLS check —
  // sanitise the filename so it can never break out of that segment.
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `${studentId}/${Date.now()}-${safeName}`

  const { error: upErr } = await supabase.storage.from('result-slips').upload(path, file)
  if (upErr) return { error: upErr.message }

  const { error } = await supabase.from('result_slips').insert({
    student_id: studentId,
    exam_name: examName,
    subject,
    score,
    max_score: maxScore,
    file_path: path,
    uploaded_by: user.id,
  })
  if (error) {
    await createAdminClient().storage.from('result-slips').remove([path])
    return { error: error.message }
  }

  revalidatePath(`/parent/results/${studentId}`)
  return { error: null }
}

export async function sendParentMessage(
  studentId: string,
  subject: string,
  body: string,
): Promise<{ error: string | null }> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const trimmed = body.trim()
  if (!trimmed) return { error: 'Message cannot be empty.' }

  const { error } = await supabase.from('messages').insert({
    sender_id: user.id,
    student_id: studentId,
    recipient_id: null,
    subject: subject.trim() || null,
    body: trimmed,
  })
  if (error) return { error: error.message }

  revalidatePath(`/parent/messages/${studentId}`)
  return { error: null }
}
