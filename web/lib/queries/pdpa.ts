/* eslint-disable @typescript-eslint/no-explicit-any */
import { createClient } from '@/lib/supabase/server'

export type PolicyDocument = {
  title: string
  body: string
  version: string
  publishedAt: string
}

/**
 * The current Data Protection Notice (PDPA s20). Any authenticated user can
 * read `policy_documents`. Returns null if none is published yet.
 */
export async function getPrivacyNotice(): Promise<PolicyDocument | null> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('policy_documents')
    .select('title, body, version, published_at')
    .eq('doc_type', 'data_protection_notice')
    .eq('is_current', true)
    .order('published_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) {
    throw new Error(`getPrivacyNotice: ${error.message}`)
  }
  if (!data) return null
  return {
    title: data.title,
    body: data.body,
    version: data.version,
    publishedAt: data.published_at,
  }
}

export type ConsentRecord = {
  consentType: string
  status: 'granted' | 'withdrawn'
  method: string
  noticeVersion: string | null
  createdAt: string
}

/**
 * Current consent state per consent_type for a student (PDPA s13–17).
 * Reads the `current_consent` view (latest row per (student, type)).
 */
export async function getStudentConsent(studentId: string): Promise<ConsentRecord[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('current_consent')
    .select('consent_type, status, method, notice_version, created_at')
    .eq('student_id', studentId)
    .order('consent_type')

  if (error) {
    throw new Error(`getStudentConsent: ${error.message}`)
  }
  return (data ?? []).map((r: any) => ({
    consentType: r.consent_type,
    status: r.status,
    method: r.method,
    noticeVersion: r.notice_version,
    createdAt: r.created_at,
  }))
}

export type PendingCorrection = {
  id: string
  studentId: string
  studentName: string
  fieldName: string
  currentValue: string | null
  requestedValue: string | null
  createdAt: string
}

/**
 * Admin review queue: correction requests still awaiting a decision (PDPA s22).
 */
export async function getPendingCorrections(): Promise<PendingCorrection[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('correction_requests')
    .select('id, student_id, field_name, current_value, requested_value, created_at, student:students(full_name)')
    .eq('status', 'pending')
    .order('created_at', { ascending: false })

  if (error) {
    throw new Error(`getPendingCorrections: ${error.message}`)
  }
  return (data ?? []).map((r: any) => ({
    id: r.id,
    studentId: r.student_id,
    studentName: r.student?.full_name ?? 'Unknown',
    fieldName: r.field_name,
    currentValue: r.current_value,
    requestedValue: r.requested_value,
    createdAt: r.created_at,
  }))
}

