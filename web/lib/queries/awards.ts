/* eslint-disable @typescript-eslint/no-explicit-any */
import { createClient } from '@/lib/supabase/server'
import { getAttendanceSummary } from '@/lib/queries/analytics'

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

