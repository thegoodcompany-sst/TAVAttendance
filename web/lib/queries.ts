/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz, dateOffsetInTz, isTuitionDay } from '@/lib/date'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { type AttendanceStatus } from '@/lib/status'

export type StudentTodayEntry = {
  studentId: string
  fullName: string
  classNames: string[]
  status: AttendanceStatus
  markedAt: string | null
}

async function getRosterForDate(date: string): Promise<StudentTodayEntry[]> {
  const supabase = await createClient()

  // PERF-06: use the pre-aggregated `get_roster_for_date` RPC (migration 014)
  // instead of selecting the full nested sessions→enrollments→records tree, which
  // PostgREST's max_rows cap does not bound for nested relations. The RPC does the
  // worst-status merge and class-name aggregation in SQL and returns one row per
  // student (already deactivation-filtered, matching the former QA-02 behaviour).
  const { data, error } = await supabase.rpc('get_roster_for_date', { p_date: date })

  if (error) {
    throw new Error(`getRosterForDate: ${error.message}`)
  }

  return (data ?? []).map((r: any) => ({
    studentId: r.student_id,
    fullName: r.full_name,
    classNames: (r.class_names as string[]) ?? [],
    status: (r.status ?? null) as AttendanceStatus,
    markedAt: r.marked_at ?? null,
  }))
}

export const getTodayRoster = cache((): Promise<StudentTodayEntry[]> => getRosterForDate(todayInTz()))

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

  // There is no direct FK between `sessions` and `enrollments` — both reference
  // `classes` (sessions.class_id, enrollments.class_id). PostgREST cannot infer an
  // indirect relationship, so enrollments must be embedded through the class:
  // sessions → classes → enrollments. Embedding it directly on `sessions` 500s the
  // whole dashboard with PGRST200 ("Could not find a relationship").
  const { data, error } = await supabase
    .from('sessions')
    .select(`
      id,
      class:classes!inner(name, schedule_time, is_study_space, enrollments:enrollments(is_active)),
      attendance_records(status)
    `)
    .eq('session_date', today)
    // Study Space attendance is internal-only — never surface it in reports (migration 015).
    .eq('class.is_study_space', false)

  if (error) {
    throw new Error(`getTodaySessions: ${error.message}`)
  }

  return (data ?? []).map((s: any) => {
    const records: Array<{ status: string }> = s.attendance_records ?? []
    // Enrollments are left-joined (not `!inner`) so a session isn't dropped
    // just because every enrollment for its class has since been deactivated.
    const total = ((s.class?.enrollments as any[]) ?? []).filter(e => e.is_active).length
    return {
      sessionId: s.id,
      className: s.class?.name ?? 'Unknown',
      scheduleTime: s.class?.schedule_time ?? '',
      presentCount: records.filter(r => r.status === 'present').length,
      lateCount:    records.filter(r => r.status === 'late').length,
      absentCount:  records.filter(r => r.status === 'absent').length,
      excusedCount: records.filter(r => r.status === 'excused').length,
      notHereCount: Math.max(0, total - records.length),
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
    .select('id, status, marked_at, session:sessions!inner(session_date, class:classes!inner(name, is_study_space))')
    .eq('student_id', studentId)
    // Exclude internal Study Space attendance from student history (migration 015).
    .eq('session.class.is_study_space', false)
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
    .maybeSingle()

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
    .select('session_date, class:classes!inner(is_study_space), attendance_records(status)')
    // Exclude internal Study Space sessions from the dashboard chart (migration 015).
    .eq('class.is_study_space', false)
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

  // test_mode ON shows every day (demo/testing creates weekend sessions);
  // OFF keeps the chart to real tuition days so test noise stays hidden.
  const testMode = await isFeatureEnabled('test_mode')

  return Array.from(map.entries())
    .filter(([date]) => testMode || isTuitionDay(date))
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, counts]) => ({ date, ...counts }))
}

// ── Analytics ─────────────────────────────────────────────────────────────

export type AttendanceSummaryRow = {
  studentId: string
  studentName: string
  classId: string
  className: string
  totalSessions: number
  presentCount: number
  lateCount: number
  absentCount: number
  excusedCount: number
  attendancePct: number | null
}

/**
 * Every per-student-per-class row from the `attendance_summary` view. The view
 * already excludes study-space, inactive students, and inactive classes at
 * source (migration 016), so this is safe to read directly.
 */
export const getAttendanceSummary = cache(async (): Promise<AttendanceSummaryRow[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('attendance_summary')
    .select('student_id, student_name, class_id, class_name, total_sessions, present_count, late_count, absent_count, excused_count, attendance_pct')
    .order('class_name')

  if (error) {
    throw new Error(`getAttendanceSummary: ${error.message}`)
  }

  return (data ?? []).map((r: any) => ({
    studentId: r.student_id,
    studentName: r.student_name,
    classId: r.class_id,
    className: r.class_name,
    totalSessions: r.total_sessions,
    presentCount: r.present_count,
    lateCount: r.late_count,
    absentCount: r.absent_count,
    excusedCount: r.excused_count,
    attendancePct: r.attendance_pct,
  }))
})

export type StudentMonthlyDrop = {
  studentId: string
  studentName: string
  thisMonthPct: number
  lastMonthPct: number
  delta: number
  thisMonthSessions: number
  lastMonthSessions: number
}

/**
 * Per-student attendance % for this calendar month vs last, so the page can
 * answer "whose attendance dropped this month". Reads attendance_records
 * through sessions with an inner join on classes to exclude study space
 * (migration 015). Only students with sessions in BOTH months are returned —
 * a delta needs two comparable points — sorted biggest drop first.
 */
export async function getMonthlyAttendanceDrops(): Promise<StudentMonthlyDrop[]> {
  const supabase = await createClient()
  const today = todayInTz()
  const thisMonthStart = `${today.slice(0, 7)}-01`
  const [y, m] = today.split('-').map(Number)
  const lastMonthStart = m === 1
    ? `${y - 1}-12-01`
    : `${y}-${String(m - 1).padStart(2, '0')}-01`

  const { data, error } = await supabase
    .from('attendance_records')
    .select('status, student_id, student:students!inner(full_name, is_active), session:sessions!inner(session_date, class:classes!inner(is_study_space, is_active))')
    .eq('session.class.is_study_space', false)
    .eq('session.class.is_active', true)
    .eq('student.is_active', true)
    .gte('session.session_date', lastMonthStart)
    .lte('session.session_date', today)

  if (error) {
    throw new Error(`getMonthlyAttendanceDrops: ${error.message}`)
  }

  const testMode = await isFeatureEnabled('test_mode')

  // attended = present|late|excused, matching the attendance_summary definition.
  type Bucket = { total: number; attended: number }
  const agg = new Map<string, { name: string; thisM: Bucket; lastM: Bucket }>()
  for (const r of (data ?? []) as any[]) {
    const date: string = r.session?.session_date ?? ''
    if (!date) continue
    // Same rule as getDailyAttendance: hide non-tuition-day (test) records unless test_mode is ON.
    if (!testMode && !isTuitionDay(date)) continue
    const entry = agg.get(r.student_id) ?? {
      name: r.student?.full_name ?? 'Unknown',
      thisM: { total: 0, attended: 0 },
      lastM: { total: 0, attended: 0 },
    }
    const bucket = date >= thisMonthStart ? entry.thisM : entry.lastM
    bucket.total++
    if (r.status === 'present' || r.status === 'late' || r.status === 'excused') bucket.attended++
    agg.set(r.student_id, entry)
  }

  const pct = (b: Bucket) => Math.round((b.attended / b.total) * 1000) / 10

  return Array.from(agg.entries())
    .filter(([, v]) => v.thisM.total > 0 && v.lastM.total > 0)
    .map(([studentId, v]) => {
      const thisMonthPct = pct(v.thisM)
      const lastMonthPct = pct(v.lastM)
      return {
        studentId,
        studentName: v.name,
        thisMonthPct,
        lastMonthPct,
        delta: Math.round((thisMonthPct - lastMonthPct) * 10) / 10,
        thisMonthSessions: v.thisM.total,
        lastMonthSessions: v.lastM.total,
      }
    })
    .sort((a, b) => a.delta - b.delta)
}