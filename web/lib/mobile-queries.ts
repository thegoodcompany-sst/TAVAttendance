/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { todayInTz } from '@/lib/date'
import type { AttendanceStatus } from '@/lib/status'

type MobileProfile = {
  role: string
  fullName: string
}

export const getMobileProfile = cache(async (): Promise<MobileProfile | null> => {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  const { data, error } = await supabase
    .from('profiles')
    .select('role, full_name')
    .eq('id', user.id)
    .maybeSingle()
  if (error) throw new Error(`getMobileProfile: ${error.message}`)
  if (!data) return null
  return { role: data.role, fullName: data.full_name }
})

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
  absenceInformed: boolean | null
}

function mobileClass(row: any): MobileClass {
  return {
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
  }
}

export const getMobileClasses = cache(async (): Promise<MobileClass[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase
    .rpc('get_my_classes')
  if (error) throw new Error(`getMobileClasses: ${error.message}`)
  return (data ?? []).map(mobileClass)
})

export async function getMobileClass(classId: string): Promise<{ classInfo: MobileClass; sessions: MobileSession[] } | null> {
  const supabase = await createClient()
  const [classes, { data: sessions, error: sessionError }] = await Promise.all([
    getMobileClasses(),
    supabase
      .from('sessions')
      .select('id, class_id, session_date, notes, started_at, ended_at')
      .eq('class_id', classId)
      .order('session_date', { ascending: false })
      .limit(24),
  ])
  if (sessionError) throw new Error(`getMobileClass sessions: ${sessionError.message}`)
  const cls = classes.find(row => row.id === classId)
  if (!cls) return null
  return {
    classInfo: cls,
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
  const [classes, { data: roster, error: rosterError }] = await Promise.all([
    getMobileClasses(),
    supabase.rpc('get_session_roster', { p_session_id: sessionId }),
  ])
  if (rosterError) throw new Error(`getMobileSession roster: ${rosterError.message}`)
  const cls = classes.find(row => row.id === session.class_id)
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
    classInfo: cls,
    roster: (roster ?? []).map((row: any) => ({
      studentId: row.student_id,
      fullName: row.full_name,
      status: row.status as AttendanceStatus,
      markedAt: row.marked_at,
      lateReason: row.late_reason,
      absenceInformed: (row.absence_informed ?? null) as boolean | null,
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
  const [{ data: sessions, error }, classes] = await Promise.all([
    supabase
      .from('sessions')
      .select('id, class_id')
      .eq('session_date', todayInTz()),
    getMobileClasses(),
  ])
  if (error) throw new Error(`getMobileSignInEntries: ${error.message}`)
  const classNames = new Map<string, string>(
    classes
      .filter(cls => cls.canOperateTodaySession)
      .map(cls => [cls.id, cls.name])
  )

  const merged = new Map<string, KioskEntry>()
  const rank: Record<string, number> = { late: 3, present: 2, absent: 1 }
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
          absenceInformed: (row.absence_informed ?? null) as boolean | null,
          sessionIds: [session.id],
          classNames: [classNames.get(session.class_id) ?? 'Class'],
        })
      } else {
        existing.sessionIds.push(session.id)
        existing.classNames.push(classNames.get(session.class_id) ?? 'Class')
        if (incoming && (!existing.status || rank[incoming] > rank[existing.status])) existing.status = incoming
        if (row.marked_at && (!existing.markedAt || row.marked_at > existing.markedAt)) existing.markedAt = row.marked_at
        if (row.late_reason) existing.lateReason = row.late_reason
        if (existing.absenceInformed == null && row.absence_informed != null) {
          existing.absenceInformed = row.absence_informed as boolean
        }
      }
    }
  }))
  return [...merged.values()].sort((a, b) => a.fullName.localeCompare(b.fullName))
}
