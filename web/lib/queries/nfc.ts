import { createClient } from '@/lib/supabase/server'

export type StudentNfcBinding = {
  chipUidSuffix: string
  issuedAt: string
}

/**
 * Active NFC binding for one student. Suffix only — never the full chip UID.
 * Throws on query failure so the page cannot look like "no card".
 */
export async function getStudentNfcBinding(studentId: string): Promise<StudentNfcBinding | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_student_nfc_binding', {
    p_student_id: studentId,
  })
  if (error) {
    throw new Error(`getStudentNfcBinding: ${error.message}`)
  }
  if (!data) return null
  const row = data as { chip_uid_suffix?: string; issued_at?: string }
  if (!row.chip_uid_suffix || !row.issued_at) return null
  return { chipUidSuffix: row.chip_uid_suffix, issuedAt: row.issued_at }
}
