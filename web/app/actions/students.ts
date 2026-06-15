'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

// NRIC/FIN pattern — mirrors the server-side DB trigger reject_nric_in_notes()
// so we can give a friendly message before hitting the database.
const NRIC_RE = /\b[STFGM][0-9]{7}[A-Z]\b/i

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' as const, supabase, user: null }

  const { data: profile } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') {
    return { error: 'Only admins can perform this action.' as const, supabase, user: null }
  }
  return { error: null, supabase, user }
}

async function currentNoticeVersion(
  supabase: Awaited<ReturnType<typeof createClient>>
): Promise<string | null> {
  const { data } = await supabase
    .from('policy_documents')
    .select('version')
    .eq('doc_type', 'data_protection_notice')
    .eq('is_current', true)
    .order('published_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  return data?.version ?? null
}

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
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr }

  const fullName = input.fullName.trim()
  if (!fullName) return { error: 'Student name is required.' }

  if (!consentAttested) {
    return { error: 'Parent/guardian consent must be attested before creating a student.' }
  }

  if (input.notes && NRIC_RE.test(input.notes)) {
    return { error: 'Notes appear to contain an NRIC/FIN. Do not store national identifiers (PDPA).' }
  }

  const { data: student, error: insertErr } = await supabase
    .from('students')
    .insert({
      full_name: fullName,
      date_of_birth: input.dateOfBirth || null,
      school: input.school?.trim() || null,
      year_of_study: input.yearOfStudy?.trim() || null,
      notes: input.notes?.trim() || null,
    })
    .select('id')
    .single()

  if (insertErr) return { error: insertErr.message }

  const noticeVersion = await currentNoticeVersion(supabase)
  const { error: consentErr } = await supabase.from('consent_records').insert({
    student_id: student.id,
    consent_type: 'data_collection',
    status: 'granted',
    method: 'admin_attestation',
    notice_version: noticeVersion,
    granted_by: user!.id,
  })
  if (consentErr) return { error: `Student created but consent log failed: ${consentErr.message}` }

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
  const { error: authErr, supabase, user } = await requireAdmin()
  if (authErr) return { error: authErr, created: 0, skipped: [] }

  if (!consentAttested) {
    return {
      error: 'Parent/guardian consent must be attested for all imported students.',
      created: 0,
      skipped: [],
    }
  }

  const noticeVersion = await currentNoticeVersion(supabase)
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

    const { data: student, error: insertErr } = await supabase
      .from('students')
      .insert({
        full_name: fullName,
        date_of_birth: r.dateOfBirth || null,
        school: r.school?.trim() || null,
        year_of_study: r.yearOfStudy?.trim() || null,
        notes: r.notes?.trim() || null,
      })
      .select('id')
      .single()

    if (insertErr || !student) {
      skipped.push({ row: i + 1, reason: insertErr?.message ?? 'Insert failed' })
      continue
    }

    const { error: consentErr } = await supabase.from('consent_records').insert({
      student_id: student.id,
      consent_type: 'data_collection',
      status: 'granted',
      method: 'admin_attestation',
      notice_version: noticeVersion,
      granted_by: user!.id,
      source_note: 'bulk_import',
    })
    if (consentErr) {
      skipped.push({ row: i + 1, reason: `Consent log failed: ${consentErr.message}` })
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

  const { error } = await supabase.rpc('erase_student', { p_student_id: studentId })
  if (error) return { error: error.message }

  revalidatePath('/students')
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
