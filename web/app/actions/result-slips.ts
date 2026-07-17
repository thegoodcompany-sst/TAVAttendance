'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'

export async function acknowledgeSlip(id: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase
    .from('result_slips')
    .update({ acknowledged_by: user!.id, acknowledged_at: new Date().toISOString() })
    .eq('id', id)
  if (error) return { error: error.message }

  revalidatePath('/result-slips')
  return { error: null }
}
