'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin } from '@/lib/admin'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { normalizeNfcChipUid } from '@/lib/nfc-chip-uid'

export async function pairNfcChip(
  studentId: string,
  chipUid: string
): Promise<{ error: string | null; suffix: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr, suffix: null }
  if (!(await isFeatureEnabled('nfc_sign_in'))) {
    return { error: 'NFC sign-in is disabled.', suffix: null }
  }

  const uid = normalizeNfcChipUid(chipUid)
  if (!uid) {
    return { error: 'Enter the chip UID shown on the station (8–20 hex characters).', suffix: null }
  }

  const { data, error } = await supabase.rpc('pair_nfc_chip', {
    p_student_id: studentId,
    p_chip_uid: uid,
  })
  if (error) return { error: error.message, suffix: null }

  const suffix = (data as { chip_uid_suffix?: string } | null)?.chip_uid_suffix ?? null
  revalidatePath(`/students/${studentId}`)
  return { error: null, suffix }
}

export async function revokeNfcChip(
  studentId: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }
  if (!(await isFeatureEnabled('nfc_sign_in'))) {
    return { error: 'NFC sign-in is disabled.' }
  }

  const { error } = await supabase.rpc('revoke_nfc_chip_for_student', {
    p_student_id: studentId,
  })
  if (error) return { error: error.message }

  revalidatePath(`/students/${studentId}`)
  return { error: null }
}
