'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin, NRIC_RE } from '@/lib/admin'
import {
  acknowledgeStudentStorageCleanup,
  removeStudentPrivateFiles,
} from '@/lib/storage-cleanup'
import { createAdminClient } from '@/lib/supabase/admin'

export type StudentInput = {
  fullName: string
  dateOfBirth?: string | null
  school?: string | null
  yearOfStudy?: string | null
  notes?: string | null
}

/**
 * Create one student with the PDPA consent attestation gate (s13–17).
 * Blocks if `consentAttested` is false; on success writes a granted
 * `consent_records` row tied to the current notice version.
 */
export async function createStudent(
  input: StudentInput,
  consentAttested: boolean
): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const fullName = input.fullName.trim()
  if (!fullName) return { error: 'Student name is required.' }

  if (!consentAttested) {
    return { error: 'Parent/guardian consent must be attested before creating a student.' }
  }

  if (input.notes && NRIC_RE.test(input.notes)) {
    return { error: 'Notes appear to contain an NRIC/FIN. Do not store national identifiers (PDPA).' }
  }

  const { error } = await supabase.rpc('create_student_with_consent', {
    p_full_name: fullName,
    p_date_of_birth: input.dateOfBirth || null,
    p_school: input.school?.trim() || null,
    p_year_of_study: input.yearOfStudy?.trim() || null,
    p_notes: input.notes?.trim() || null,
    p_source_note: 'Admin attestation on create',
  })
  if (error) return { error: error.message }

  revalidatePath('/students')
  return { error: null }
}

export type BulkImportResult = {
  error: string | null
  created: number
  skipped: { row: number; reason: string }[]
}

/**
 * Bulk import students from parsed CSV rows. The same consent attestation
 * gate applies — the admin attests that consent was obtained offline for all
 * rows. One granted consent_records row is written per created student.
 */
export async function bulkImportStudents(
  rows: StudentInput[],
  consentAttested: boolean
): Promise<BulkImportResult> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr, created: 0, skipped: [] }

  if (!consentAttested) {
    return {
      error: 'Parent/guardian consent must be attested for all imported students.',
      created: 0,
      skipped: [],
    }
  }

  const skipped: { row: number; reason: string }[] = []
  let created = 0

  for (let i = 0; i < rows.length; i++) {
    const r = rows[i]
    const fullName = r.fullName?.trim()
    if (!fullName) {
      skipped.push({ row: i + 1, reason: 'Missing name' })
      continue
    }
    if (r.notes && NRIC_RE.test(r.notes)) {
      skipped.push({ row: i + 1, reason: 'Notes contain an NRIC/FIN' })
      continue
    }

    const { error } = await supabase.rpc('create_student_with_consent', {
      p_full_name: fullName,
      p_date_of_birth: r.dateOfBirth || null,
      p_school: r.school?.trim() || null,
      p_year_of_study: r.yearOfStudy?.trim() || null,
      p_notes: r.notes?.trim() || null,
      p_source_note: 'bulk_import',
    })
    if (error) {
      skipped.push({ row: i + 1, reason: error.message })
      continue
    }
    created++
  }

  revalidatePath('/students')
  return { error: null, created, skipped }
}

/**
 * Withdraw a consent (PDPA s16). Appends a `withdrawn` row to the ledger.
 */
export async function withdrawConsent(
  studentId: string,
  consentType: string
): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase.rpc('record_admin_consent', {
    p_student_id: studentId,
    p_consent_type: consentType,
    p_status: 'withdrawn',
    p_source_note: 'Admin withdrawal',
  })
  if (error) return { error: error.message }

  revalidatePath(`/students/${studentId}`)
  return { error: null }
}

/**
 * Pseudonymise a student (legacy RPC name retained for compatibility) —
 * redacts direct identifiers and rotates the attendance identity, but retains
 * longitudinal session facts that may remain linkable in a small cohort.
 */
export async function anonymiseStudent(studentId: string): Promise<{ error: string | null }> {
  const { error: authErr, user } = await requireAdmin()
  if (authErr || !user) return { error: authErr ?? 'Not authenticated.' }

  const adminClient = createAdminClient()

  try {
    await removeStudentPrivateFiles(adminClient, studentId)
  } catch (error) {
    return { error: error instanceof Error ? error.message : 'Could not erase private files.' }
  }

  const { error } = await adminClient.rpc('anonymise_student_secure', {
    p_student_id: studentId,
    p_actor_id: user.id,
  })
  if (error) return { error: error.message }
  revalidatePath('/students')

  try {
    // The database mutation removes parent links and the student row, so
    // untrusted clients can no longer upload into this prefix. Sweep again to
    // catch an object uploaded between the preflight sweep and the RPC commit.
    await removeStudentPrivateFiles(adminClient, studentId)
    await acknowledgeStudentStorageCleanup(adminClient, studentId)
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'Unknown Storage error.'
    return { error: `Student pseudonymised, but final private-file cleanup failed: ${detail}` }
  }

  return { error: null }
}

/**
 * Hard erase a student (PDPA s25, explicit erasure request) — deletes the
 * record and scrubs audit snapshots through the trusted server-only workflow.
 */
export async function eraseStudent(studentId: string): Promise<{ error: string | null }> {
  const { error: authErr, user } = await requireAdmin()
  if (authErr || !user) return { error: authErr ?? 'Not authenticated.' }

  const adminClient = createAdminClient()

  try {
    await removeStudentPrivateFiles(adminClient, studentId)
    await acknowledgeStudentStorageCleanup(adminClient, studentId)
  } catch (error) {
    return { error: error instanceof Error ? error.message : 'Could not erase private files.' }
  }

  const { error } = await adminClient.rpc('erase_student_secure', {
    p_student_id: studentId,
    p_actor_id: user.id,
  })
  if (error) return { error: error.message }
  revalidatePath('/students')

  try {
    await removeStudentPrivateFiles(adminClient, studentId)
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'Unknown Storage error.'
    return { error: `Student erased, but final private-file cleanup failed: ${detail}` }
  }

  return { error: null }
}

/**
 * Subject-access export (PDPA s21) — returns the full personal-data bundle for
 * a student as a JSON string. The RPC also logs a data_disclosures row.
 */
export async function exportStudentData(
  studentId: string
): Promise<{ error: string | null; json: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr, json: null }

  const { data, error } = await supabase.rpc('export_student_personal_data', {
    p_student_id: studentId,
  })
  if (error) return { error: error.message, json: null }

  return { error: null, json: JSON.stringify(data, null, 2) }
}
