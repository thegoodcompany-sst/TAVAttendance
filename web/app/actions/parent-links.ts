'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'

export async function linkParentStudent(parentId: string, studentId: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase.rpc('link_parent_student', { p_parent: parentId, p_student: studentId })
  if (error) return { error: error.message }

  revalidatePath('/users')
  return { error: null }
}

export async function unlinkParentStudent(parentId: string, studentId: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase.rpc('unlink_parent_student', { p_parent: parentId, p_student: studentId })
  if (error) return { error: error.message }

  revalidatePath('/users')
  return { error: null }
}
