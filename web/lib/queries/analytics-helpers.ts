import { isTuitionDay, weekStartOf } from '../date'

/** Count present / late / excused statuses from a list of status strings. */
export function countAttendanceStatuses(statuses: Array<string | null | undefined>): {
  present: number
  late: number
  excused: number
} {
  let present = 0
  let late = 0
  let excused = 0
  for (const status of statuses) {
    if (status === 'present') present++
    else if (status === 'late') late++
    else if (status === 'excused') excused++
  }
  return { present, late, excused }
}

/** Tuition-day filter used by daily/monthly/weekly analytics. */
export function filterDatesByTuitionDay(
  dates: string[],
  testMode: boolean,
): string[] {
  return dates.filter((date) => testMode || isTuitionDay(date))
}

/** Attendance percentage rounded to one decimal; zero total → 0 (not NaN/Infinity). */
export function attendancePct(attended: number, total: number): number {
  if (total <= 0) return 0
  return Math.round((attended / total) * 1000) / 10
}

/**
 * Monthly comparison keeps only students with sessions in both periods.
 * `delta` is thisMonthPct − lastMonthPct (negative = drop).
 */
export function monthlyDropsFromBuckets(
  rows: Array<{
    studentId: string
    studentName: string
    thisMonth: { total: number; attended: number }
    lastMonth: { total: number; attended: number }
  }>,
): Array<{
  studentId: string
  studentName: string
  thisMonthPct: number
  lastMonthPct: number
  delta: number
  thisMonthSessions: number
  lastMonthSessions: number
}> {
  return rows
    .filter((r) => r.thisMonth.total > 0 && r.lastMonth.total > 0)
    .map((r) => {
      const thisMonthPct = attendancePct(r.thisMonth.attended, r.thisMonth.total)
      const lastMonthPct = attendancePct(r.lastMonth.attended, r.lastMonth.total)
      return {
        studentId: r.studentId,
        studentName: r.studentName,
        thisMonthPct,
        lastMonthPct,
        delta: Math.round((thisMonthPct - lastMonthPct) * 10) / 10,
        thisMonthSessions: r.thisMonth.total,
        lastMonthSessions: r.lastMonth.total,
      }
    })
    .sort((a, b) => a.delta - b.delta)
}

/** Aggregate attendance by Monday week start. Weeks with zero records are omitted. */
export function weeklyAttendanceFromRecords(
  records: Array<{ date: string; status: string }>,
): Array<{ weekStart: string; attendancePct: number; totalRecords: number }> {
  const agg = new Map<string, { total: number; attended: number }>()
  for (const r of records) {
    const week = weekStartOf(r.date)
    const bucket = agg.get(week) ?? { total: 0, attended: 0 }
    bucket.total++
    if (r.status === 'present' || r.status === 'late' || r.status === 'excused') {
      bucket.attended++
    }
    agg.set(week, bucket)
  }
  return Array.from(agg.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([weekStart, b]) => ({
      weekStart,
      attendancePct: attendancePct(b.attended, b.total),
      totalRecords: b.total,
    }))
}

