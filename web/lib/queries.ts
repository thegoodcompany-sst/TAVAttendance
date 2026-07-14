/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz, dateOffsetInTz, isTuitionDay, weekStartOf } from '@/lib/date'
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
  notes: string | null
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
      notes,
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
      notes: s.notes ?? null,
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

export type StudentResult = {
  studentId: string
  subject: 'Math' | 'English'
  grade: string
}

// Read-only surface for tutor-entered grades (migration 023). Entry is iOS-only.
export async function getStudentResults(studentId?: string): Promise<StudentResult[]> {
  const supabase = await createClient()
  let query = supabase.from('student_results').select('student_id, subject, grade')
  if (studentId) query = query.eq('student_id', studentId)
  const { data, error } = await query

  if (error) {
    throw new Error(`getStudentResults: ${error.message}`)
  }

  return (data ?? []).map((r: any) => ({
    studentId: r.student_id,
    subject: r.subject,
    grade: r.grade,
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

// ── Awards ──────────────────────────────────────────────────────────────

export type AwardCandidate = {
  studentId: string
  studentName: string
  totalSessions: number
  attendancePct: number
  lateCount: number
}

/**
 * Award candidates aggregated from the `attendance_summary` view, which already
 * excludes study-space, inactive students and inactive classes (migration 016).
 * ponytail: the view is all-time, so ranking is lifetime — `period` on the award
 * row is the filing label, not a re-filter. Swap to per-month record queries if
 * awards must reflect a single month's attendance.
 */
export async function getAwardCandidates(): Promise<AwardCandidate[]> {
  const rows = await getAttendanceSummary()
  const agg = new Map<string, { name: string; total: number; attended: number; late: number }>()
  for (const r of rows) {
    const e = agg.get(r.studentId) ?? { name: r.studentName, total: 0, attended: 0, late: 0 }
    e.total += r.totalSessions
    e.attended += r.presentCount + r.lateCount + r.excusedCount
    e.late += r.lateCount
    agg.set(r.studentId, e)
  }
  return Array.from(agg.entries())
    .filter(([, v]) => v.total > 0)
    .map(([studentId, v]) => ({
      studentId,
      studentName: v.name,
      totalSessions: v.total,
      attendancePct: Math.round((v.attended / v.total) * 1000) / 10,
      lateCount: v.late,
    }))
}

export type GivenAward = {
  id: string
  studentId: string
  studentName: string
  awardType: string
  awardedAt: string
}

export async function getAwardsForPeriod(period: string): Promise<GivenAward[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('awards')
    .select('id, student_id, award_type, awarded_at, student:students(full_name)')
    .eq('period', period)
    .order('awarded_at', { ascending: false })

  if (error) {
    throw new Error(`getAwardsForPeriod: ${error.message}`)
  }
  return (data ?? []).map((r: any) => ({
    id: r.id,
    studentId: r.student_id,
    studentName: r.student?.full_name ?? 'Unknown',
    awardType: r.award_type,
    awardedAt: r.awarded_at,
  }))
}

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

export type WeeklyAttendancePoint = {
  weekStart: string
  attendancePct: number
  totalRecords: number
}

/**
 * Centre-wide attendance % per ISO week (Monday start) over the last `weeks`
 * weeks, for the analytics trend line. Same filters as
 * getMonthlyAttendanceDrops: study space excluded (invariant), inactive
 * classes/students excluded, non-tuition days hidden unless test_mode is ON.
 * Weeks with no records are omitted — a % of zero sessions is meaningless.
 */
export async function getWeeklyAttendanceTrend(weeks = 12): Promise<WeeklyAttendancePoint[]> {
  const supabase = await createClient()
  const today = todayInTz()
  const startDate = weekStartOf(dateOffsetInTz(-7 * (weeks - 1)))

  const { data, error } = await supabase
    .from('attendance_records')
    .select('status, student:students!inner(is_active), session:sessions!inner(session_date, class:classes!inner(is_study_space, is_active))')
    .eq('session.class.is_study_space', false)
    .eq('session.class.is_active', true)
    .eq('student.is_active', true)
    .gte('session.session_date', startDate)
    .lte('session.session_date', today)

  if (error) {
    throw new Error(`getWeeklyAttendanceTrend: ${error.message}`)
  }

  const testMode = await isFeatureEnabled('test_mode')

  const agg = new Map<string, { total: number; attended: number }>()
  for (const r of (data ?? []) as any[]) {
    const date: string = r.session?.session_date ?? ''
    if (!date) continue
    if (!testMode && !isTuitionDay(date)) continue
    const week = weekStartOf(date)
    const bucket = agg.get(week) ?? { total: 0, attended: 0 }
    bucket.total++
    if (r.status === 'present' || r.status === 'late' || r.status === 'excused') bucket.attended++
    agg.set(week, bucket)
  }

  return Array.from(agg.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([weekStart, b]) => ({
      weekStart,
      attendancePct: Math.round((b.attended / b.total) * 1000) / 10,
      totalRecords: b.total,
    }))
}

export type AuditLogEntry = {
  id: string
  tableName: string
  recordId: string
  action: 'INSERT' | 'UPDATE' | 'DELETE'
  oldData: Record<string, unknown> | null
  newData: Record<string, unknown> | null
  changedBy: string | null
  changedAt: string
  actorName: string
  actorRole: string | null
}

export async function getAuditLog({
  user,
  table,
  limit = 50,
  before,
}: {
  user?: string
  table?: string
  limit?: number
  before?: string
} = {}): Promise<AuditLogEntry[]> {
  const supabase = await createClient()
  let query = supabase
    .from('audit_log')
    .select('id, table_name, record_id, action, old_data, new_data, changed_by, changed_at')
    .order('changed_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 100))

  if (user) query = query.eq('changed_by', user)
  if (table) query = query.eq('table_name', table)
  if (before) {
    const separator = before.lastIndexOf('|')
    const beforeAt = before.slice(0, separator)
    const beforeId = before.slice(separator + 1)
    if (separator > 0 && !Number.isNaN(Date.parse(beforeAt)) && /^[0-9a-f-]{36}$/i.test(beforeId)) {
      query = query.or(`changed_at.lt.${beforeAt},and(changed_at.eq.${beforeAt},id.lt.${beforeId})`)
    }
  }

  const { data, error } = await query
  if (error) throw new Error(`getAuditLog: ${error.message}`)

  const actorIds = [...new Set((data ?? []).map((row: any) => row.changed_by).filter(Boolean))]
  const actors = new Map<string, { fullName: string; role: string }>()
  if (actorIds.length > 0) {
    const { data: profiles, error: profilesError } = await supabase
      .from('profiles')
      .select('id, full_name, role')
      .in('id', actorIds)
    if (profilesError) throw new Error(`getAuditLog profiles: ${profilesError.message}`)
    for (const profile of profiles ?? []) {
      actors.set(profile.id, { fullName: profile.full_name, role: profile.role })
    }
  }

  return (data ?? []).map((row: any) => {
    const actor = row.changed_by ? actors.get(row.changed_by) : null
    return {
      id: row.id,
      tableName: row.table_name,
      recordId: row.record_id,
      action: row.action,
      oldData: row.old_data,
      newData: row.new_data,
      changedBy: row.changed_by,
      changedAt: row.changed_at,
      actorName: actor?.fullName ?? 'System',
      actorRole: actor?.role ?? null,
    }
  })
}

export type AuditActor = { id: string; fullName: string; role: string }

export const getAuditActors = cache(async (): Promise<AuditActor[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, role')
    .order('full_name')
  if (error) throw new Error(`getAuditActors: ${error.message}`)
  return (data ?? []).map((profile: any) => ({
    id: profile.id,
    fullName: profile.full_name,
    role: profile.role,
  }))
})

export type RecentAppEvent = {
  id: string
  occurredAt: string
  platform: 'ios' | 'android' | 'web'
  eventType: 'screen_view' | 'tap' | 'error' | 'crash' | 'ops' | 'latency'
  name: string
  role: string | null
  properties: Record<string, unknown>
}

export async function getRecentEvents({
  platform,
  type,
  limit = 50,
}: {
  platform?: string
  type?: string
  limit?: number
} = {}): Promise<RecentAppEvent[]> {
  const supabase = await createClient()
  let query = supabase
    .from('app_events')
    .select('id, occurred_at, platform, event_type, name, role, properties')
    .order('occurred_at', { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 100))

  if (platform && ['ios', 'android', 'web'].includes(platform)) query = query.eq('platform', platform)
  if (type && ['screen_view', 'tap', 'error', 'crash', 'ops', 'latency'].includes(type)) query = query.eq('event_type', type)

  const { data, error } = await query
  if (error) throw new Error(`getRecentEvents: ${error.message}`)
  return (data ?? []).map((row: any) => ({
    id: row.id,
    occurredAt: row.occurred_at,
    platform: row.platform,
    eventType: row.event_type,
    name: row.name,
    role: row.role,
    properties: row.properties ?? {},
  }))
}

export type HealthMetric = {
  current: number
  previous: number
  delta: number
}

export type HealthMetrics = {
  eventCount: HealthMetric
  errorRate: HealthMetric
  crashes: HealthMetric
  syncAttempts: HealthMetric
  syncFailureRate: HealthMetric
  latencies: Array<{ name: string } & HealthMetric>
  syncTotals: { synced: number; skipped: number; blockedEndedSession: number; pendingBefore: number }
  daily: Array<{ date: string; events: number; errors: number }>
}

function percentDelta(current: number, previous: number): number {
  if (previous === 0) return current === 0 ? 0 : 100
  return Math.round(((current - previous) / previous) * 1000) / 10
}

export async function getHealthMetrics(): Promise<HealthMetrics> {
  const supabase = await createClient()
  const today = todayInTz()
  const currentStart = weekStartOf(today)
  const previousStart = weekStartOf(dateOffsetInTz(-7))
  const previousEnd = new Date(Date.parse(`${currentStart}T00:00:00Z`) - 86_400_000).toISOString().slice(0, 10)

  const [{ data: dailyRows, error: dailyError }, { data: syncRows, error: syncError }] = await Promise.all([
    supabase
      .from('app_events_daily')
      .select('event_date, event_type, name, event_count, duration_ms_p95')
      .gte('event_date', previousStart)
      .lte('event_date', today),
    supabase
      .from('app_events')
      .select('occurred_at, name, properties')
      .in('name', ['sync_result', 'sync_failure'])
      .gte('occurred_at', `${previousStart}T00:00:00+08:00`),
  ])

  if (dailyError) throw new Error(`getHealthMetrics daily: ${dailyError.message}`)
  if (syncError) throw new Error(`getHealthMetrics sync: ${syncError.message}`)

  const rows = (dailyRows ?? []) as any[]
  const periodRows = (start: string, end?: string) => rows.filter(row =>
    row.event_date >= start && (!end || row.event_date <= end)
  )
  const count = (items: any[], predicate?: (row: any) => boolean) => items.reduce(
    (sum, row) => sum + (!predicate || predicate(row) ? Number(row.event_count) : 0),
    0,
  )
  const metric = (current: number, previous: number): HealthMetric => ({
    current,
    previous,
    delta: percentDelta(current, previous),
  })

  const currentRows = periodRows(currentStart)
  const previousRows = periodRows(previousStart, previousEnd)
  const currentEvents = count(currentRows)
  const previousEvents = count(previousRows)
  const currentErrors = count(currentRows, row => row.event_type === 'error')
  const previousErrors = count(previousRows, row => row.event_type === 'error')
  const currentCrashes = count(currentRows, row => row.event_type === 'crash')
  const previousCrashes = count(previousRows, row => row.event_type === 'crash')

  const sync = (syncRows ?? []) as any[]
  const singaporeDate = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
  const syncInPeriod = (start: string, end?: string) => sync.filter(row => {
    const date = singaporeDate.format(new Date(row.occurred_at))
    return date >= start && (!end || date <= end)
  })
  const syncFailureRate = (items: any[]) => {
    const failures = items.filter(row => row.name === 'sync_failure').length
    const attempts = items.filter(row => row.name === 'sync_failure' || row.name === 'sync_result').length
    return attempts > 0 ? Math.round((failures / attempts) * 1000) / 10 : 0
  }

  const latencyNames = [...new Set(rows.filter(row => row.duration_ms_p95 != null).map(row => row.name as string))]
  const latencyFor = (items: any[], name: string) => Math.max(
    0,
    ...items.filter(row => row.name === name).map(row => Number(row.duration_ms_p95) || 0),
  )

  const daily = Array.from({ length: 14 }, (_, index) => {
    const date = dateOffsetInTz(index - 13)
    const dayRows = rows.filter(row => row.event_date === date)
    return {
      date,
      events: count(dayRows),
      errors: count(dayRows, row => row.event_type === 'error' || row.event_type === 'crash'),
    }
  })

  const currentSync = syncInPeriod(currentStart)
  const previousSync = syncInPeriod(previousStart, previousEnd)
  const syncAttempts = (items: any[]) => items.filter(row => row.name === 'sync_failure' || row.name === 'sync_result').length
  const numberProperty = (row: any, key: string) => Number(row.properties?.[key]) || 0

  return {
    eventCount: metric(currentEvents, previousEvents),
    errorRate: metric(
      currentEvents > 0 ? Math.round((currentErrors / currentEvents) * 1000) / 10 : 0,
      previousEvents > 0 ? Math.round((previousErrors / previousEvents) * 1000) / 10 : 0,
    ),
    crashes: metric(currentCrashes, previousCrashes),
    syncAttempts: metric(syncAttempts(currentSync), syncAttempts(previousSync)),
    syncFailureRate: metric(syncFailureRate(currentSync), syncFailureRate(previousSync)),
    latencies: latencyNames.map(name => {
      const current = latencyFor(currentRows, name)
      const previous = latencyFor(previousRows, name)
      return { name, ...metric(current, previous) }
    }).sort((a, b) => b.current - a.current),
    syncTotals: currentSync.reduce((totals, row) => ({
      synced: totals.synced + numberProperty(row, 'synced'),
      skipped: totals.skipped + numberProperty(row, 'skipped'),
      blockedEndedSession: totals.blockedEndedSession + numberProperty(row, 'blocked_ended_session'),
      pendingBefore: totals.pendingBefore + numberProperty(row, 'pending_before'),
    }), { synced: 0, skipped: 0, blockedEndedSession: 0, pendingBefore: 0 }),
    daily,
  }
}