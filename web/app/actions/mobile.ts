'use server'

import { revalidatePath } from 'next/cache'
import { requireAdmin, requireStaff, NRIC_RE } from '@/lib/admin'
import { todayInTz } from '@/lib/date'
import type { AttendanceStatus } from '@/lib/status'

type Result = { error: string | null }

function refreshMobile(...paths: string[]) {
  revalidatePath('/mobile', 'layout')
  for (const path of paths) revalidatePath(path)
}

export async function saveClass(input: {
  id?: string
  name: string
  subject: string
  level: string
  scheduleDay: string
  scheduleTime: string
  durationMinutes: number
}): Promise<Result & { classId?: string }> {
  const { error: authError, supabase } = await requireAdmin()
  if (authError) return { error: authError }
  const name = input.name.trim()
  if (!name) return { error: 'Class name is required.' }
  const dayCodes: Record<string, string> = { Monday: 'MO', Tuesday: 'TU', Wednesday: 'WE', Thursday: 'TH', Friday: 'FR', Saturday: 'SA', Sunday: 'SU' }
  const payload = {
    name,
    subject: input.subject.trim() || null,
    level: input.level.trim() || null,
    schedule_day: input.scheduleDay || null,
    schedule_time: input.scheduleTime || null,
    duration_minutes: input.durationMinutes,
    recurrence_rule: input.scheduleDay ? `FREQ=WEEKLY;BYDAY=${dayCodes[input.scheduleDay]}` : null,
    is_active: true,
  }
  if (input.id) {
    const { error } = await supabase.from('classes').update(payload).eq('id', input.id)
    if (error) return { error: error.message }
    refreshMobile('/mobile/classes', `/mobile/classes/${input.id}`)
    return { error: null, classId: input.id }
  }
  const { data, error } = await supabase.from('classes').insert(payload).select('id').single()
  if (error) return { error: error.message }
  refreshMobile('/mobile/classes')
  return { error: null, classId: data.id }
}

export async function deactivateClass(classId: string): Promise<Result> {
  const { error: authError, supabase } = await requireAdmin()
  if (authError) return { error: authError }
  const { error } = await supabase.from('classes').update({ is_active: false }).eq('id', classId)
  if (error) return { error: error.message }
  refreshMobile('/mobile/classes')
  return { error: null }
}

export async function setClassEnrollment(classId: string, studentId: string, enrolled: boolean): Promise<Result> {
  const { error: authError, supabase } = await requireAdmin()
  if (authError) return { error: authError }
  const { error } = enrolled
    ? await supabase.from('enrollments').upsert({
        class_id: classId,
        student_id: studentId,
        is_active: true,
        unenrolled_at: null,
      }, { onConflict: 'student_id,class_id' })
    : await supabase.from('enrollments').update({
        is_active: false,
        unenrolled_at: new Date().toISOString(),
      }).eq('class_id', classId).eq('student_id', studentId)
  if (error) return { error: error.message }
  refreshMobile(`/mobile/classes/${classId}`, `/mobile/classes/${classId}/students`)
  return { error: null }
}

export async function startTodayClass(classId: string): Promise<Result & { sessionId?: string }> {
  const { error: authError, supabase } = await requireStaff()
  if (authError) return { error: authError }
  const { data: session, error } = await supabase
    .from('sessions')
    .upsert({ class_id: classId, session_date: todayInTz() }, { onConflict: 'class_id,session_date' })
    .select('id, started_at')
    .single()
  if (error) return { error: error.message }
  const { error: updateError } = await supabase
    .from('sessions')
    .update({ started_at: session.started_at ?? new Date().toISOString(), ended_at: null })
    .eq('id', session.id)
  if (updateError) return { error: updateError.message }
  refreshMobile(`/mobile/classes/${classId}`, `/mobile/sessions/${session.id}`)
  return { error: null, sessionId: session.id }
}

export async function endClass(sessionId: string): Promise<Result> {
  const { error: authError, supabase } = await requireStaff()
  if (authError) return { error: authError }
  const { error } = await supabase.from('sessions').update({ ended_at: new Date().toISOString() }).eq('id', sessionId)
  if (error) return { error: error.message }
  refreshMobile(`/mobile/sessions/${sessionId}`)
  return { error: null }
}

export async function reopenClass(sessionId: string): Promise<Result> {
  const { error: authError, supabase } = await requireStaff()
  if (authError) return { error: authError }
  const { error } = await supabase.from('sessions').update({ ended_at: null }).eq('id', sessionId)
  if (error) return { error: error.message }
  refreshMobile(`/mobile/sessions/${sessionId}`)
  return { error: null }
}

export async function markAttendance(sessionId: string, studentId: string, status: Exclude<AttendanceStatus, null>): Promise<Result> {
  const { error: authError, supabase, user } = await requireStaff()
  if (authError) return { error: authError }
  const { error } = await supabase.from('attendance_records').upsert({
    session_id: sessionId,
    student_id: studentId,
    status,
    marked_by: user!.id,
    marked_at: new Date().toISOString(),
    client_mutation_id: crypto.randomUUID(),
  }, { onConflict: 'session_id,student_id' })
  if (error) return { error: error.message }
  refreshMobile(`/mobile/sessions/${sessionId}`, '/mobile/sign-in')
  return { error: null }
}

export async function markRemainingAbsent(sessionId: string, studentIds: string[]): Promise<Result> {
  const { error: authError, supabase, user } = await requireStaff()
  if (authError) return { error: authError }
  if (studentIds.length === 0) return { error: null }
  const now = new Date().toISOString()
  const { error } = await supabase.from('attendance_records').upsert(
    studentIds.map(studentId => ({
      session_id: sessionId,
      student_id: studentId,
      status: 'absent',
      marked_by: user!.id,
      marked_at: now,
      client_mutation_id: crypto.randomUUID(),
    })),
    { onConflict: 'session_id,student_id' }
  )
  if (error) return { error: error.message }
  refreshMobile(`/mobile/sessions/${sessionId}`)
  return { error: null }
}

export async function saveMobileSessionNote(sessionId: string, notes: string): Promise<Result> {
  const { error: authError, supabase } = await requireStaff()
  if (authError) return { error: authError }
  const trimmed = notes.trim()
  if (NRIC_RE.test(trimmed)) return { error: 'Notes must not contain an NRIC/FIN.' }
  const { error } = await supabase.from('sessions').update({ notes: trimmed || null }).eq('id', sessionId)
  if (error) return { error: error.message }
  refreshMobile(`/mobile/sessions/${sessionId}`)
  return { error: null }
}

export async function updateStudent(studentId: string, input: { fullName: string; school: string; yearOfStudy: string; notes: string }): Promise<Result> {
  const { error: authError, supabase } = await requireAdmin()
  if (authError) return { error: authError }
  const fullName = input.fullName.trim()
  if (!fullName) return { error: 'Student name is required.' }
  if (NRIC_RE.test(input.notes)) return { error: 'Notes must not contain an NRIC/FIN.' }
  const { error } = await supabase.from('students').update({
    full_name: fullName,
    school: input.school.trim() || null,
    year_of_study: input.yearOfStudy.trim() || null,
    notes: input.notes.trim() || null,
  }).eq('id', studentId)
  if (error) return { error: error.message }
  refreshMobile('/mobile/students', `/mobile/students/${studentId}`)
  return { error: null }
}

export async function deactivateStudent(studentId: string): Promise<Result> {
  const { error: authError, supabase } = await requireAdmin()
  if (authError) return { error: authError }
  const { error } = await supabase.from('students').update({ is_active: false }).eq('id', studentId)
  if (error) return { error: error.message }
  refreshMobile('/mobile/students')
  return { error: null }
}

const VALID_GRADES = new Set(['AL1','AL2','AL3','AL4','AL5','AL6','AL7','AL8','A1','A2','B3','B4','C5','C6','D7','E8','F9'])
export async function saveStudentResult(studentId: string, subject: 'Math' | 'English', grade: string): Promise<Result> {
  const { error: authError, supabase, user } = await requireStaff()
  if (authError) return { error: authError }
  if (!VALID_GRADES.has(grade)) return { error: 'Choose a valid grade.' }
  const { error } = await supabase.from('student_results').upsert({
    student_id: studentId,
    subject,
    grade,
    updated_by: user!.id,
  }, { onConflict: 'student_id,subject' })
  if (error) return { error: error.message }
  refreshMobile(`/mobile/students/${studentId}`)
  return { error: null }
}

export async function deleteStudentResult(studentId: string, subject: 'Math' | 'English'): Promise<Result> {
  const { error: authError, supabase } = await requireStaff()
  if (authError) return { error: authError }
  const { error } = await supabase.from('student_results').delete().eq('student_id', studentId).eq('subject', subject)
  if (error) return { error: error.message }
  refreshMobile(`/mobile/students/${studentId}`)
  return { error: null }
}

export async function prepareSignInBoard(): Promise<Result> {
  const { error: authError, supabase } = await requireAdmin()
  if (authError) return { error: authError }
  const [{ data: classes, error: classError }, { data: testMode }] = await Promise.all([
    supabase
    .from('classes')
    .select('id, schedule_day, recurrence_rule')
    .eq('is_active', true)
    .eq('is_study_space', false),
    supabase.from('feature_flags').select('enabled').eq('key', 'test_mode').maybeSingle(),
  ])
  if (classError) return { error: classError.message }
  const weekday = new Intl.DateTimeFormat('en-SG', { timeZone: 'Asia/Singapore', weekday: 'long' }).format(new Date())
  const abbreviations: Record<string, string> = { Monday: 'MO', Tuesday: 'TU', Wednesday: 'WE', Thursday: 'TH', Friday: 'FR', Saturday: 'SA', Sunday: 'SU' }
  const code = abbreviations[weekday]
  const scheduled = (classes ?? []).filter(cls => {
    if (testMode?.enabled) return true
    const byDay = cls.recurrence_rule?.match(/(?:^|;)BYDAY=([^;]+)/)?.[1]?.split(',')
    if (byDay?.length) return byDay.includes(code)
    if (cls.schedule_day) return cls.schedule_day === weekday
    return true
  })
  if (scheduled.length === 0) return { error: null }
  const { error } = await supabase.from('sessions').upsert(
    scheduled.map(cls => ({ class_id: cls.id, session_date: todayInTz() })),
    { onConflict: 'class_id,session_date' }
  )
  if (error) return { error: error.message }
  refreshMobile('/mobile/sign-in', '/mobile/classes')
  return { error: null }
}

export async function markKioskAttendance(sessionIds: string[], studentId: string, status: Exclude<AttendanceStatus, null>): Promise<Result> {
  const { error: authError, supabase, user } = await requireAdmin()
  if (authError) return { error: authError }
  const now = new Date().toISOString()
  const { error } = await supabase.from('attendance_records').upsert(
    sessionIds.map(sessionId => ({
      session_id: sessionId,
      student_id: studentId,
      status,
      marked_by: user!.id,
      marked_at: now,
      client_mutation_id: crypto.randomUUID(),
    })),
    { onConflict: 'session_id,student_id' }
  )
  if (error) return { error: error.message }
  refreshMobile('/mobile/sign-in')
  return { error: null }
}

export async function signInKioskStudent(sessionIds: string[], studentId: string): Promise<Result & { status?: 'present' | 'late' }> {
  const { error: authError, supabase, user } = await requireAdmin()
  if (authError) return { error: authError }
  const { data: sessions, error: sessionError } = await supabase
    .from('sessions')
    .select('id, started_at, class:classes(schedule_time)')
    .in('id', sessionIds)
  if (sessionError) return { error: sessionError.message }
  const now = new Date()
  const today = todayInTz()
  let worst: 'present' | 'late' = 'present'
  const records = (sessions ?? []).map(session => {
    const relation = session.class as unknown as { schedule_time: string | null } | null
    const schedule = relation?.schedule_time
    const scheduledAt = schedule ? new Date(`${today}T${schedule}+08:00`) : null
    const status: 'present' | 'late' =
      (session.started_at && now > new Date(session.started_at)) || (scheduledAt && !Number.isNaN(scheduledAt.valueOf()) && now > scheduledAt)
        ? 'late'
        : 'present'
    if (status === 'late') worst = 'late'
    return {
      session_id: session.id,
      student_id: studentId,
      status,
      marked_by: user!.id,
      marked_at: now.toISOString(),
      client_mutation_id: crypto.randomUUID(),
    }
  })
  if (records.length === 0) return { error: 'No active session found for this student.' }
  const { error } = await supabase.from('attendance_records').upsert(records, { onConflict: 'session_id,student_id' })
  if (error) return { error: error.message }
  refreshMobile('/mobile/sign-in')
  return { error: null, status: worst }
}
