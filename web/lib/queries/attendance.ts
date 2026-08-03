/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz } from '@/lib/date'
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
      notHereCount: Math.max(0, total - records.length),
      totalEnrolled: total,
      notes: s.notes ?? null,
    }
  })
})
