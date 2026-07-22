/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz } from '@/lib/date'
import type { AttendanceStatus } from '@/lib/status'

export type MobileClass = {
  id: string
  name: string
  subject: string | null
  level: string | null
  scheduleDay: string | null
  scheduleTime: string | null
  durationMinutes: number
  recurrenceRule: string | null
  recurrenceEndDate: string | null
  canManageSessions: boolean
  canOperateTodaySession: boolean
}

export type MobileSession = {
  id: string
  classId: string
  sessionDate: string
  notes: string | null
  startedAt: string | null
  endedAt: string | null
}

export type MobileRosterEntry = {
  studentId: string
  fullName: string
  status: AttendanceStatus
  markedAt: string | null
  lateReason: string | null
}

export const getMobileClasses = cache(async (): Promise<MobileClass[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase
    .rpc('get_my_classes')
  if (error) throw new Error(`getMobileClasses: ${error.message}`)
  return (data ?? []).map((row: any) => ({
    id: row.id,
    name: row.name,
    subject: row.subject,
    level: row.level,
    scheduleDay: row.schedule_day,
    scheduleTime: row.schedule_time,
    durationMinutes: row.duration_minutes,
    recurrenceRule: row.recurrence_rule,
    recurrenceEndDate: row.recurrence_end_date,
    canManageSessions: row.can_manage_sessions === true,
    canOperateTodaySession: row.can_operate_today_session === true,
  }))
})

export async function getMobileClass(classId: string): Promise<{ classInfo: MobileClass; sessions: MobileSession[] } | null> {
  const supabase = await createClient()
  const [{ data: classes, error: classError }, { data: sessions, error: sessionError }] = await Promise.all([
    supabase.rpc('get_my_classes'),
    supabase
      .from('sessions')
      .select('id, class_id, session_date, notes, started_at, ended_at')
      .eq('class_id', classId)
      .order('session_date', { ascending: false })
      .limit(24),
  ])
  if (classError) throw new Error(`getMobileClass: ${classError.message}`)
  if (sessionError) throw new Error(`getMobileClass sessions: ${sessionError.message}`)
  const cls = (classes ?? []).find((row: any) => row.id === classId)
  if (!cls) return null
  return {
    classInfo: {
      id: cls.id,
      name: cls.name,
      subject: cls.subject,
      level: cls.level,
      scheduleDay: cls.schedule_day,
      scheduleTime: cls.schedule_time,
      durationMinutes: cls.duration_minutes,
      recurrenceRule: cls.recurrence_rule,
      recurrenceEndDate: cls.recurrence_end_date,
      canManageSessions: cls.can_manage_sessions === true,
      canOperateTodaySession: cls.can_operate_today_session === true,
    },
    sessions: (sessions ?? []).map((row: any) => ({
      id: row.id,
      classId: row.class_id,
      sessionDate: row.session_date,
      notes: row.notes,
      startedAt: row.started_at,
      endedAt: row.ended_at,
    })),
  }
}

export async function getMobileSession(sessionId: string): Promise<{ session: MobileSession; classInfo: MobileClass; roster: MobileRosterEntry[] } | null> {
  const supabase = await createClient()
  const { data: session, error } = await supabase
    .from('sessions')
    .select('id, class_id, session_date, notes, started_at, ended_at')
    .eq('id', sessionId)
    .maybeSingle()
  if (error) throw new Error(`getMobileSession: ${error.message}`)
  if (!session) return null
  const [{ data: classes, error: classError }, { data: roster, error: rosterError }] = await Promise.all([
    supabase.rpc('get_my_classes'),
    supabase.rpc('get_session_roster', { p_session_id: sessionId }),
  ])
  if (classError) throw new Error(`getMobileSession class: ${classError.message}`)
  if (rosterError) throw new Error(`getMobileSession roster: ${rosterError.message}`)
  const cls = (classes ?? []).find((row: any) => row.id === session.class_id)
  if (!cls) return null
  return {
    session: {
      id: session.id,
      classId: session.class_id,
      sessionDate: session.session_date,
      notes: session.notes,
      startedAt: session.started_at,
      endedAt: session.ended_at,
    },
    classInfo: {
      id: cls.id,
      name: cls.name,
      subject: cls.subject,
      level: cls.level,
      scheduleDay: cls.schedule_day,
      scheduleTime: cls.schedule_time,
      durationMinutes: cls.duration_minutes,
      recurrenceRule: cls.recurrence_rule,
      recurrenceEndDate: cls.recurrence_end_date,
      canManageSessions: cls.can_manage_sessions === true,
      canOperateTodaySession: cls.can_operate_today_session === true,
    },
    roster: (roster ?? []).map((row: any) => ({
      studentId: row.student_id,
      fullName: row.full_name,
      status: row.status as AttendanceStatus,
      markedAt: row.marked_at,
      lateReason: row.late_reason,
    })),
  }
}

export async function getMobileEnrollmentData(classId: string) {
  const supabase = await createClient()
  const [{ data: students, error: studentError }, { data: enrollments, error: enrollmentError }] = await Promise.all([
    supabase.from('students').select('id, full_name, school, year_of_study').eq('is_active', true).order('full_name'),
    supabase.from('enrollments').select('student_id').eq('class_id', classId).eq('is_active', true),
  ])
  if (studentError) throw new Error(`getMobileEnrollmentData students: ${studentError.message}`)
  if (enrollmentError) throw new Error(`getMobileEnrollmentData enrollments: ${enrollmentError.message}`)
  return {
    students: (students ?? []).map(row => ({ id: row.id, fullName: row.full_name, school: row.school, yearOfStudy: row.year_of_study })),
    enrolledIds: (enrollments ?? []).map(row => row.student_id),
  }
}

export type KioskEntry = MobileRosterEntry & {
  sessionIds: string[]
  classNames: string[]
}

export async function getMobileSignInEntries(): Promise<KioskEntry[]> {
  const supabase = await createClient()
  const [{ data: sessions, error }, { data: classes, error: classError }] = await Promise.all([
    supabase
      .from('sessions')
      .select('id, class_id')
      .eq('session_date', todayInTz()),
    supabase.rpc('get_my_classes'),
  ])
  if (error) throw new Error(`getMobileSignInEntries: ${error.message}`)
  if (classError) throw new Error(`getMobileSignInEntries classes: ${classError.message}`)
  const classNames = new Map<string, string>(
    (classes ?? []).map((cls: { id: string; name: string }): [string, string] => [cls.id, cls.name])
  )

  const merged = new Map<string, KioskEntry>()
  const rank: Record<string, number> = { late: 4, present: 3, absent: 2, excused: 1 }
  await Promise.all((sessions ?? []).filter(session => classNames.has(session.class_id)).map(async (session: any) => {
    const { data: roster, error: rosterError } = await supabase.rpc('get_session_roster', { p_session_id: session.id })
    if (rosterError) throw new Error(`getMobileSignInEntries roster: ${rosterError.message}`)
    for (const row of roster ?? []) {
      const existing = merged.get(row.student_id)
      const incoming = row.status as AttendanceStatus
      if (!existing) {
        merged.set(row.student_id, {
          studentId: row.student_id,
          fullName: row.full_name,
          status: incoming,
          markedAt: row.marked_at,
          lateReason: row.late_reason,
          sessionIds: [session.id],
          classNames: [classNames.get(session.class_id) ?? 'Class'],
        })
      } else {
        existing.sessionIds.push(session.id)
        existing.classNames.push(classNames.get(session.class_id) ?? 'Class')
        if (incoming && (!existing.status || rank[incoming] > rank[existing.status])) existing.status = incoming
        if (row.marked_at && (!existing.markedAt || row.marked_at > existing.markedAt)) existing.markedAt = row.marked_at
        if (row.late_reason) existing.lateReason = row.late_reason
      }
    }
  }))
  return [...merged.values()].sort((a, b) => a.fullName.localeCompare(b.fullName))
}
