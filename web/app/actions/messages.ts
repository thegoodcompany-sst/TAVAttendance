'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'

export async function replyToThread(
  studentId: string,
  subject: string,
  body: string,
): Promise<{ error: string | null }> {
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const trimmed = body.trim()
  if (!trimmed) return { error: 'Message cannot be empty.' }

  const { error } = await supabase.from('messages').insert({
    sender_id: user!.id,
    student_id: studentId,
    recipient_id: null,
    subject: subject.trim() || null,
    body: trimmed,
  })
  if (error) return { error: error.message }

  revalidatePath(`/messages/${studentId}`)
  return { error: null }
}
