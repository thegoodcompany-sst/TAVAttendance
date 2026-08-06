import type { AttendanceStatus } from '@/lib/status'

export type YearHistoryRecord = {
  id: string
  status: AttendanceStatus
  absenceInformed: boolean | null
  markedAt: string
  sessionDate: string
  classId: string
  className: string
}

export type ClassYearSummary = {
  classId: string
  className: string
  totalSessions: number
  presentCount: number
  lateCount: number
  absentCount: number
  attendancePct: number | null
}

/** Rolling 12 months back from Singapore "today" as YYYY-MM-DD. */
export function yearWindowStart(now = new Date(), tz = 'Asia/Singapore'): string {
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now)
  const [y, m, d] = today.split('-').map(Number)
  // UTC midnight of that calendar day one year earlier (leap-day clamps via Date).
  const then = new Date(Date.UTC(y - 1, m - 1, d))
  return then.toISOString().slice(0, 10)
}

/**
 * Groups history by class, sorted by class name. Matches iOS StudentYearSummary
 * and the attendance_summary formula: (present + late) / total, 1 decimal.
 */
export function summarizeByClass(records: YearHistoryRecord[]): ClassYearSummary[] {
  const buckets = new Map<string, {
    classId: string
    className: string
    present: number
    late: number
    absent: number
    total: number
  }>()

  for (const record of records) {
    if (!record.status) continue
    const key = record.classId || record.className
    const bucket = buckets.get(key) ?? {
      classId: record.classId,
      className: record.className,
      present: 0,
      late: 0,
      absent: 0,
      total: 0,
    }
    bucket.total += 1
    if (record.status === 'present') bucket.present += 1
    else if (record.status === 'late') bucket.late += 1
    else if (record.status === 'absent') bucket.absent += 1
    buckets.set(key, bucket)
  }

  return [...buckets.values()]
    .sort((a, b) => a.className.localeCompare(b.className))
    .map(b => ({
      classId: b.classId,
      className: b.className,
      totalSessions: b.total,
      presentCount: b.present,
      lateCount: b.late,
      absentCount: b.absent,
      attendancePct: b.total === 0
        ? null
        : Math.round((1000 * (b.present + b.late)) / b.total) / 10,
    }))
}
