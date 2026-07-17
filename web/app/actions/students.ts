'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin, NRIC_RE } from '@/lib/admin'

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
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const { error } = await supabase.from('consent_records').insert({
    student_id: studentId,
    consent_type: consentType,
    status: 'withdrawn',
    method: 'admin_attestation',
    granted_by: user!.id,
  })
  if (error) return { error: error.message }

  revalidatePath(`/students/${studentId}`)
  return { error: null }
}

/**
 * Anonymise a student (PDPA s25 retention) — redacts PII, keeps anonymous
 * attendance. Default erasure path. Calls the admin-guarded RPC.
 */
export async function anonymiseStudent(studentId: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const storageError = await removeStudentStorage(supabase, studentId)
  if (storageError) return { error: storageError }

  const { error } = await supabase.rpc('anonymise_student', { p_student_id: studentId })
  if (error) return { error: error.message }

  revalidatePath('/students')
  return { error: null }
}

/**
 * Hard erase a student (PDPA s25, explicit erasure request) — deletes the
 * record and scrubs audit snapshots. Calls the admin-guarded RPC.
 */
export async function eraseStudent(studentId: string): Promise<{ error: string | null }> {
  const { error: authErr, supabase } = await requireAdmin()
  if (authErr) return { error: authErr }

  const storageError = await removeStudentStorage(supabase, studentId)
  if (storageError) return { error: storageError }

  const { error } = await supabase.rpc('erase_student', { p_student_id: studentId })
  if (error) return { error: error.message }

  revalidatePath('/students')
  return { error: null }
}

async function removeStudentStorage(
  supabase: Awaited<ReturnType<typeof requireAdmin>>['supabase'],
  studentId: string
): Promise<string | null> {
  for (const bucketName of ['result-slips', 'student-photos']) {
    const bucket = supabase.storage.from(bucketName)
    for (const folder of new Set([studentId.toLowerCase(), studentId.toUpperCase()])) {
      while (true) {
        const { data: objects, error: listError } = await bucket.list(folder, {
          limit: 100,
          offset: 0,
        })
        if (listError) return `Could not inspect ${bucketName}: ${listError.message}`

        const files = (objects ?? [])
          .filter((object) => object.id)
          .map((object) => `${folder}/${object.name}`)
        if (files.length > 0) {
          const { error: removeError } = await bucket.remove(files)
          if (removeError) return `Could not erase ${bucketName}: ${removeError.message}`
        }
        if ((objects?.length ?? 0) < 100 || files.length === 0) break
      }
    }
  }
  return null
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
