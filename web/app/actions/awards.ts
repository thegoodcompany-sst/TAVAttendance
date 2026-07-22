'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'
import { isFeatureEnabled } from '@/lib/feature-flags'

export type AwardType = 'perfect_attendance' | 'punctuality'

export async function giveAward(
  studentId: string,
  awardType: AwardType,
  period: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }
  if (!(await isFeatureEnabled('awards'))) return { error: 'Awards are not enabled.' }

  if (awardType !== 'perfect_attendance' && awardType !== 'punctuality') {
    return { error: 'Unknown award type.' }
  }
  if (!/^\d{4}-\d{2}$/.test(period)) return { error: 'Invalid period.' }

  const { data: existing, error: lookupErr } = await supabase
    .from('awards')
    .select('id')
    .eq('student_id', studentId)
    .eq('award_type', awardType)
    .eq('period', period)
    .maybeSingle()
  if (lookupErr) return { error: lookupErr.message }
  if (existing) return { error: 'Award already given for this period.' }

  const { error } = await supabase.from('awards').insert({
    student_id: studentId,
    award_type: awardType,
    period,
    awarded_by: user!.id,
  })
  if (error) return { error: error.message }

  revalidatePath('/awards')
  return { error: null }
}
