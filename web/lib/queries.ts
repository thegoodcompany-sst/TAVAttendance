/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz, yesterdayInTz, dateOffsetInTz } from '@/lib/date'
import { worstStatus, type AttendanceStatus } from '@/lib/status'

export type StudentTodayEntry = {
  studentId: string
  fullName: string
  classNames: string[]
  status: AttendanceStatus
  markedAt: string | null
}

async function getRosterForDate(date: string): Promise<StudentTodayEntry[]> {
  const supabase = await createClient()

  const { data, error } = await supabase
    .from('sessions')
    .select(`
      id,
      class:classes(name, schedule_time),
      attendance_records(student_id, status, marked_at),
      enrollments!inner(student_id, is_active, student:students(id, full_name, is_active))
    `)
    .eq('session_date', date)
    .eq('enrollments.is_active', true)

  if (error) {
    throw new Error(`getRosterForDate: ${error.message}`)
  }

  const map = new Map<string, StudentTodayEntry>()

  for (const session of data ?? []) {
    const className = (session.class as any)?.name ?? 'Unknown'
    const enrollments = (session.enrollments as any[]) ?? []

    for (const enr of enrollments) {
      const student = enr.student
      if (!student) continue
      // QA-02: skip students who have been deactivated even if enrollment is
      // still active — mirrors the iOS kiosk behaviour.
      if (student.is_active === false) continue
      const sid = student.id
      const rec = (session.attendance_records as any[])?.find(
        (r: any) => r.student_id === sid
      )
      const recordStatus: AttendanceStatus = rec?.status ?? null
      const markedAt: string | null = rec?.marked_at ?? null

      const existing = map.get(sid)
      if (!existing) {
        map.set(sid, {
          studentId: sid,
          fullName: student.full_name,
          classNames: [className],
          status: recordStatus,
          markedAt,
        })
      } else {
        const merged = worstStatus(existing.status, recordStatus)
        map.set(sid, {
          ...existing,
          classNames: existing.classNames.includes(className)
            ? existing.classNames
            : [...existing.classNames, className],
          status: merged,
          markedAt: merged === recordStatus ? markedAt : existing.markedAt,
        })
      }
    }
  }

  return Array.from(map.values()).sort((a, b) =>
    a.fullName.localeCompare(b.fullName)
  )
}

export const getTodayRoster = cache((): Promise<StudentTodayEntry[]> => getRosterForDate(todayInTz()))

export const getYesterdayRoster = cache((): Promise<StudentTodayEntry[]> => getRosterForDate(yesterdayInTz()))

export type SessionSummary = {
  sessionId: string
  className: string
  scheduleTime: string
  presentCount: number
  lateCount: number
  absentCount: number
  excusedCount: number
  notHereCount: number
  totalEnrolled: number
}

export const getTodaySessions = cache(async (): Promise<SessionSummary[]> => {
  const supabase = await createClient()
  const today = todayInTz()

  const { data, error } = await supabase
    .from('sessions')
    .select(`
      id,
      class:classes(name, schedule_time),
      attendance_records(status),
      enrollments:enrollments!inner(is_active)
    `)
    .eq('session_date', today)
    .eq('enrollments.is_active', true)

  if (error) {
    throw new Error(`getTodaySessions: ${error.message}`)
  }

  return (data ?? []).map((s: any) => {
    const records: Array<{ status: string }> = s.attendance_records ?? []
    const total = (s.enrollments as any[])?.length ?? 0
    return {
      sessionId: s.id,
      className: s.class?.name ?? 'Unknown',
      scheduleTime: s.class?.schedule_time ?? '',
      presentCount: records.filter(r => r.status === 'present').length,
      lateCount:    records.filter(r => r.status === 'late').length,
      absentCount:  records.filter(r => r.status === 'absent').length,
      excusedCount: records.filter(r => r.status === 'excused').length,
      notHereCount: total - records.length,
      totalEnrolled: total,
    }
  })
})

export type StudentRow = {
  id: string
  fullName: string
  school: string | null
  yearOfStudy: string | null
}

export const getAllStudents = cache(async (): Promise<StudentRow[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('students')
    .select('id, full_name, school, year_of_study')
    .eq('is_active', true)
    .order('full_name')

  if (error) {
    throw new Error(`getAllStudents: ${error.message}`)
  }

  return (data ?? []).map((s: any) => ({
    id: s.id,
    fullName: s.full_name,
    school: s.school,
    yearOfStudy: s.year_of_study,
  }))
})

export type ClassSummary = {
  classId: string
  className: string
  totalSessions: number
  presentCount: number
  lateCount: number
  absentCount: number
  excusedCount: number
  attendancePct: number | null
}

export async function getStudentClassSummary(studentId: string): Promise<ClassSummary[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('attendance_summary')
    .select('class_id, class_name, total_sessions, present_count, late_count, absent_count, excused_count, attendance_pct')
    .eq('student_id', studentId)
    .order('class_name')

  if (error) {
    throw new Error(`getStudentClassSummary: ${error.message}`)
  }

  return (data ?? []).map((r: any) => ({
    classId: r.class_id,
    className: r.class_name,
    totalSessions: r.total_sessions,
    presentCount: r.present_count,
    lateCount: r.late_count,
    absentCount: r.absent_count,
    excusedCount: r.excused_count,
    attendancePct: r.attendance_pct,
  }))
}

export type AttendanceRecord = {
  id: string
  status: AttendanceStatus
  markedAt: string
  sessionDate: string
  className: string
}

export async function getStudentRecentRecords(studentId: string): Promise<AttendanceRecord[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('attendance_records')
    .select('id, status, marked_at, session:sessions(session_date, class:classes(name))')
    .eq('student_id', studentId)
    .order('marked_at', { ascending: false })
    .limit(50)

  if (error) {
    throw new Error(`getStudentRecentRecords: ${error.message}`)
  }

  return (data ?? []).map((r: any) => ({
    id: r.id,
    status: r.status as AttendanceStatus,
    markedAt: r.marked_at,
    sessionDate: r.session?.session_date ?? '',
    className: r.session?.class?.name ?? 'Unknown',
  }))
}

export async function getStudent(id: string) {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('students')
    .select('id, full_name, school, year_of_study, notes')
    .eq('id', id)
    .single()

  if (error) {
    throw new Error(`getStudent: ${error.message}`)
  }
  return data
}

// ── PDPA ────────────────────────────────────────────────────────────────

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

export type DailyAttendancePoint = {
  date: string
  present: number
  late: number
}

export async function getDailyAttendance(days = 14): Promise<DailyAttendancePoint[]> {
  const supabase = await createClient()
  const today = todayInTz()

  // QA-07 / SP-03: derive the start date using calendar arithmetic in the
  // Singapore timezone so that near-midnight the window is never off by a day.
  // dateOffsetInTz(-(days-1)) gives the SGT calendar date (days-1) days ago.
  const startDate = dateOffsetInTz(-(days - 1))

  const { data, error } = await supabase
    .from('sessions')
    .select('session_date, attendance_records(status)')
    .gte('session_date', startDate)
    .lte('session_date', today)

  if (error) {
    throw new Error(`getDailyAttendance: ${error.message}`)
  }

  // Pre-populate the map with every SGT calendar date in the window so days
  // with no sessions still appear in the output with zero counts.
  const map = new Map<string, { present: number; late: number }>()
  for (let i = 0; i < days; i++) {
    const dateStr = dateOffsetInTz(-(days - 1 - i))
    map.set(dateStr, { present: 0, late: 0 })
  }

  for (const session of data ?? []) {
    const entry = map.get(session.session_date) ?? { present: 0, late: 0 }
    for (const rec of (session.attendance_records as any[]) ?? []) {
      if (rec.status === 'present') entry.present++
      else if (rec.status === 'late') entry.late++
    }
    map.set(session.session_date, entry)
  }

  return Array.from(map.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, counts]) => ({ date, ...counts }))
}