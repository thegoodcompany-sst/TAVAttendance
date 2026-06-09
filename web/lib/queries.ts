/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz, yesterdayInTz } from '@/lib/date'
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
      enrollments!inner(student_id, is_active, student:students(id, full_name))
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

export type DailyAttendancePoint = {
  date: string
  present: number
  late: number
}

export async function getDailyAttendance(days = 14): Promise<DailyAttendancePoint[]> {
  const supabase = await createClient()
  const today = todayInTz()

  const startDate = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(Date.now() - (days - 1) * 86400000))

  const { data, error } = await supabase
    .from('sessions')
    .select('session_date, attendance_records(status)')
    .gte('session_date', startDate)
    .lte('session_date', today)

  if (error) {
    throw new Error(`getDailyAttendance: ${error.message}`)
  }

  const map = new Map<string, { present: number; late: number }>()

  for (let i = 0; i < days; i++) {
    const d = new Date(Date.now() - (days - 1 - i) * 86400000)
    const dateStr = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Singapore',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(d)
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