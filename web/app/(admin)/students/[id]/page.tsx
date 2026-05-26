import { notFound } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { getStudent, getStudentClassSummary, getStudentRecentRecords } from '@/lib/queries'
import { StatusBadge } from '@/components/status-badge'
import { Avatar } from '@/components/dashboard/avatar'

export const dynamic = 'force-dynamic'

function PctBadge({ pct }: { pct: number | null }) {
  if (pct === null) return <span className="text-muted-foreground">—</span>
  const color =
    pct >= 80 ? 'text-emerald-600' :
    pct >= 60 ? 'text-amber-500' :
    'text-rose-500'
  return <span className={`font-semibold ${color}`}>{pct}%</span>
}

export default async function StudentDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const [student, classSummary, recentRecords] = await Promise.all([
    getStudent(id),
    getStudentClassSummary(id),
    getStudentRecentRecords(id),
  ])

  if (!student) notFound()

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <Link
        href="/students"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <ArrowLeft size={14} />
        All students
      </Link>

      {/* Header */}
      <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)] flex items-center gap-5">
        <Avatar name={student.full_name} size="lg" />
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-bold">{student.full_name}</h1>
          {(student.school || student.year_of_study) && (
            <p className="text-sm text-muted-foreground mt-0.5">
              {[student.school, student.year_of_study].filter(Boolean).join(' · ')}
            </p>
          )}
          {student.notes && (
            <p className="mt-3 text-sm text-muted-foreground bg-muted rounded-xl px-3 py-2">
              {student.notes}
            </p>
          )}
        </div>
      </div>

      {/* Class summary */}
      <div>
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">
          Attendance by class
        </p>
        {classSummary.length === 0 ? (
          <div className="bg-white rounded-3xl p-10 text-center shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
            <p className="text-sm text-muted-foreground">No attendance records yet.</p>
          </div>
        ) : (
          <div className="bg-white rounded-3xl overflow-hidden shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left font-medium text-muted-foreground px-5 py-3.5">Class</th>
                  <th className="text-right font-medium text-muted-foreground px-5 py-3.5">Sessions</th>
                  <th className="text-right font-medium text-muted-foreground px-5 py-3.5 hidden sm:table-cell">Present</th>
                  <th className="text-right font-medium text-muted-foreground px-5 py-3.5 hidden sm:table-cell">Late</th>
                  <th className="text-right font-medium text-muted-foreground px-5 py-3.5 hidden sm:table-cell">Absent</th>
                  <th className="text-right font-medium text-muted-foreground px-5 py-3.5">Rate</th>
                </tr>
              </thead>
              <tbody>
                {classSummary.map((c, i) => (
                  <tr
                    key={c.classId}
                    className={i < classSummary.length - 1 ? 'border-b border-border/50' : ''}
                  >
                    <td className="px-5 py-3.5 font-medium">{c.className}</td>
                    <td className="px-5 py-3.5 text-right text-muted-foreground">{c.totalSessions}</td>
                    <td className="px-5 py-3.5 text-right text-emerald-600 hidden sm:table-cell">{c.presentCount}</td>
                    <td className="px-5 py-3.5 text-right text-amber-500 hidden sm:table-cell">{c.lateCount}</td>
                    <td className="px-5 py-3.5 text-right text-rose-500 hidden sm:table-cell">{c.absentCount}</td>
                    <td className="px-5 py-3.5 text-right">
                      <PctBadge pct={c.attendancePct} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Recent records */}
      <div>
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">
          Recent records
        </p>
        {recentRecords.length === 0 ? (
          <div className="bg-white rounded-3xl p-10 text-center shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
            <p className="text-sm text-muted-foreground">No records found.</p>
          </div>
        ) : (
          <div className="bg-white rounded-3xl overflow-hidden shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left font-medium text-muted-foreground px-5 py-3.5">Date</th>
                  <th className="text-left font-medium text-muted-foreground px-5 py-3.5">Class</th>
                  <th className="text-left font-medium text-muted-foreground px-5 py-3.5">Status</th>
                  <th className="text-right font-medium text-muted-foreground px-5 py-3.5 hidden sm:table-cell">Time</th>
                </tr>
              </thead>
              <tbody>
                {recentRecords.map((r, i) => (
                  <tr
                    key={r.id}
                    className={i < recentRecords.length - 1 ? 'border-b border-border/50' : ''}
                  >
                    <td className="px-5 py-3.5 text-muted-foreground font-mono text-xs">{r.sessionDate}</td>
                    <td className="px-5 py-3.5">{r.className}</td>
                    <td className="px-5 py-3.5"><StatusBadge status={r.status} /></td>
                    <td className="px-5 py-3.5 text-right text-muted-foreground text-xs hidden sm:table-cell">
                      {new Date(r.markedAt).toLocaleTimeString('en-SG', {
                        hour: '2-digit',
                        minute: '2-digit',
                        timeZone: 'Asia/Singapore',
                      })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
