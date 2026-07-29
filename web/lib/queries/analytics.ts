/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz, dateOffsetInTz, isTuitionDay, weekStartOf } from '@/lib/date'
import { isFeatureEnabled } from '@/lib/feature-flags'
import {
  countAttendanceStatuses,
  filterDatesByTuitionDay,
  monthlyDropsFromBuckets,
  weeklyAttendanceFromRecords,
} from '@/lib/queries/analytics-helpers'

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
    const counts = countAttendanceStatuses(
      ((session.attendance_records as any[]) ?? []).map((rec: any) => rec.status),
    )
    entry.present += counts.present
    entry.late += counts.late
    map.set(session.session_date, entry)
  }

  // test_mode ON shows every day (demo/testing creates weekend sessions);
  // OFF keeps the chart to real tuition days so test noise stays hidden.
  const testMode = await isFeatureEnabled('test_mode')

  return Array.from(map.entries())
    .filter(([date]) => filterDatesByTuitionDay([date], testMode).length > 0)
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

  return monthlyDropsFromBuckets(
    Array.from(agg.entries()).map(([studentId, v]) => ({
      studentId,
      studentName: v.name,
      thisMonth: v.thisM,
      lastMonth: v.lastM,
    })),
  )
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

  const records: Array<{ date: string; status: string }> = []
  for (const r of (data ?? []) as any[]) {
    const date: string = r.session?.session_date ?? ''
    if (!date) continue
    if (!testMode && !isTuitionDay(date)) continue
    records.push({ date, status: r.status })
  }
  return weeklyAttendanceFromRecords(records)
}

