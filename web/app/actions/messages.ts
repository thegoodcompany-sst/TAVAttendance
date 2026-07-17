'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'

export async function replyToThread(
  studentId: string,
  subject: string,
  body: string,
  recipientId?: string,
): Promise<{ error: string | null }> {
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const trimmed = body.trim()
  if (!trimmed) return { error: 'Message cannot be empty.' }
  if (!recipientId) return { error: 'Parent recipient is required.' }

  const { data: link } = await supabase
    .from('parent_student_links')
    .select('id')
    .eq('parent_id', recipientId)
    .eq('student_id', studentId)
    .maybeSingle()
  if (!link) return { error: 'That parent is not linked to this student.' }

  const { error } = await supabase.from('messages').insert({
    sender_id: user!.id,
    student_id: studentId,
    recipient_id: recipientId,
    subject: subject.trim() || null,
    body: trimmed,
  })
  if (error) return { error: error.message }

  revalidatePath(`/messages/${studentId}`)
  return { error: null }
}
