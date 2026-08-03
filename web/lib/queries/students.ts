/* eslint-disable @typescript-eslint/no-explicit-any */
import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'
import { type AttendanceStatus } from '@/lib/status'

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
  attendancePct: number | null
}

export async function getStudentClassSummary(studentId: string): Promise<ClassSummary[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('attendance_summary')
    .select('class_id, class_name, total_sessions, present_count, late_count, absent_count, attendance_pct')
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
