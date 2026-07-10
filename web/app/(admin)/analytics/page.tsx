import { PageHeader } from '@/components/dashboard/page-header'
import { KpiTile } from '@/components/dashboard/kpi-tile'
import { getAttendanceSummary, getMonthlyAttendanceDrops } from '@/lib/queries'
import {
  ClassAttendanceChart,
  StudentAttendanceTable,
  type ClassStat,
  type StudentStat,
} from './analytics-client'

export const dynamic = 'force-dynamic'

function pct(attended: number, total: number): number {
  return total > 0 ? Math.round((attended / total) * 1000) / 10 : 0
}

export default async function AnalyticsPage() {
  const [summary, drops] = await Promise.all([
    getAttendanceSummary(),
    getMonthlyAttendanceDrops(),
  ])

  // attended = present + late + excused, matching the attendance_summary view.
  const attendedOf = (r: { presentCount: number; lateCount: number; excusedCount: number }) =>
    r.presentCount + r.lateCount + r.excusedCount

  const classMap = new Map<string, { className: string; total: number; attended: number; students: number }>()
  const studentMap = new Map<string, { studentName: string; total: number; attended: number; classes: number }>()

  for (const r of summary) {
    const c = classMap.get(r.classId) ?? { className: r.className, total: 0, attended: 0, students: 0 }
    c.total += r.totalSessions
    c.attended += attendedOf(r)
    c.students += 1
    classMap.set(r.classId, c)

    const s = studentMap.get(r.studentId) ?? { studentName: r.studentName, total: 0, attended: 0, classes: 0 }
    s.total += r.totalSessions
    s.attended += attendedOf(r)
    s.classes += 1
    studentMap.set(r.studentId, s)
  }

  const classes: ClassStat[] = Array.from(classMap.entries())
    .map(([classId, c]) => ({
      classId,
      className: c.className,
      attendancePct: pct(c.attended, c.total),
      totalSessions: c.total,
      students: c.students,
    }))
    .sort((a, b) => b.attendancePct - a.attendancePct)

  const students: StudentStat[] = Array.from(studentMap.entries()).map(([studentId, s]) => ({
    studentId,
    studentName: s.studentName,
    classCount: s.classes,
    totalSessions: s.total,
    attendancePct: pct(s.attended, s.total),
  }))

  const totalSessions = summary.reduce((n, r) => n + r.totalSessions, 0)
  const totalAttended = summary.reduce((n, r) => n + attendedOf(r), 0)
  const biggestDrops = drops.filter(d => d.delta < 0).slice(0, 8)

  return (
    <div className="max-w-7xl mx-auto space-y-6">
      <PageHeader title="Analytics" subtitle="Attendance across all classes" />

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <KpiTile label="Students" value={students.length} />
        <KpiTile label="Classes" value={classes.length} />
        <KpiTile label="Sessions" value={totalSessions} />
        <KpiTile label="Overall attendance" value={`${pct(totalAttended, totalSessions)}%`} accent />
      </div>

      <div className="flex flex-col lg:flex-row gap-6">
        <div className="flex-[2] bg-white rounded-3xl p-6 shadow-card min-w-0">
          <h2 className="font-display text-lg font-semibold mb-1">Attendance by class</h2>
          <p className="text-xs text-muted-foreground mb-4">Present, late or excused as a share of all sessions</p>
          {classes.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">No attendance recorded yet.</p>
          ) : (
            <ClassAttendanceChart classes={classes} />
          )}
        </div>

        <div className="flex-1 bg-white rounded-3xl p-6 shadow-card min-w-0">
          <h2 className="font-display text-lg font-semibold mb-1">Biggest drops this month</h2>
          <p className="text-xs text-muted-foreground mb-4">Attendance vs last month</p>
          {biggestDrops.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-12">No students down on last month.</p>
          ) : (
            <div className="space-y-1">
              {biggestDrops.map(d => (
                <div key={d.studentId} className="flex items-center gap-3 px-3 py-2.5 rounded-2xl hover:bg-muted/50 transition-colors">
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{d.studentName}</p>
                    <p className="text-xs text-muted-foreground tabular-nums">
                      {d.lastMonthPct}% → {d.thisMonthPct}%
                    </p>
                  </div>
                  <span className="text-sm font-semibold text-rose-600 tabular-nums">{d.delta}%</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="bg-white rounded-3xl p-6 shadow-card">
        <h2 className="font-display text-lg font-semibold mb-4">Attendance by student</h2>
        {students.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-12">No attendance recorded yet.</p>
        ) : (
          <StudentAttendanceTable students={students} />
        )}
      </div>
    </div>
  )
}
