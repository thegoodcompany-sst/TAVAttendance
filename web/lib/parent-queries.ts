import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'

export type ParentChild = {
  id: string
  fullName: string
  school: string | null
  yearOfStudy: string | null
}

export const getParentChildren = cache(async (): Promise<ParentChild[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_parent_children')
  if (error) throw new Error(`getParentChildren: ${error.message}`)

  return (data ?? []).map((row: {
    id: string
    full_name: string
    school: string | null
    year_of_study: string | null
  }) => ({
    id: row.id,
    fullName: row.full_name,
    school: row.school,
    yearOfStudy: row.year_of_study,
  }))
})

export async function getParentChild(studentId: string): Promise<ParentChild | null> {
  return (await getParentChildren()).find(child => child.id === studentId) ?? null
}

export type ParentClassSummary = {
  classId: string
  className: string
  totalSessions: number
  presentCount: number
  lateCount: number
  absentCount: number
  excusedCount: number
  attendancePct: number | null
}

export async function getParentStudentClassSummary(
  studentId: string,
): Promise<ParentClassSummary[]> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_parent_attendance_summary', {
    p_student_id: studentId,
  })
  if (error) throw new Error(`getParentStudentClassSummary: ${error.message}`)

  return (data ?? []).map((row: {
    class_id: string
    class_name: string
    total_sessions: number
    present_count: number
    late_count: number
    absent_count: number
    excused_count: number
    attendance_pct: number | null
  }) => ({
    classId: row.class_id,
    className: row.class_name,
    totalSessions: row.total_sessions,
    presentCount: row.present_count,
    lateCount: row.late_count,
    absentCount: row.absent_count,
    excusedCount: row.excused_count,
    attendancePct: row.attendance_pct,
  }))
}
