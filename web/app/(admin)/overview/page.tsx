import { AutoRefresh } from '@/components/auto-refresh'
import { StatusBadge } from '@/components/status-badge'
import { Avatar } from '@/components/dashboard/avatar'
import { PageHeader } from '@/components/dashboard/page-header'
import { getTodayRoster, type StudentTodayEntry } from '@/lib/queries'

export const dynamic = 'force-dynamic'

function StudentCard({ student }: { student: StudentTodayEntry }) {
  return (
    <div className="flex items-center gap-3 px-3 py-2.5 rounded-2xl hover:bg-muted/50 transition-colors">
      <Avatar name={student.fullName} size="sm" />
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{student.fullName}</p>
        <p className="text-xs text-muted-foreground truncate">{student.classNames.join(' · ')}</p>
      </div>
      <StatusBadge status={student.status} />
    </div>
  )
}

function Column({
  title,
  count,
  students,
  emptyText,
  accent,
}: {
  title: string
  count: number
  students: StudentTodayEntry[]
  emptyText: string
  accent: string
}) {
  return (
    <div className="bg-white rounded-[1.25rem] p-5 shadow-card flex flex-col">
      <div className="flex items-center justify-between mb-4">
        <h3 className={`text-sm font-semibold ${accent}`}>{title}</h3>
        <span className="bg-muted rounded-full px-2.5 py-0.5 text-xs font-medium text-muted-foreground">
          {count}
        </span>
      </div>
      {students.length === 0 ? (
        <p className="text-xs text-muted-foreground text-center py-8">{emptyText}</p>
      ) : (
        <div className="space-y-0.5">
          {students.map(s => (
            <StudentCard key={s.studentId} student={s} />
          ))}
        </div>
      )}
    </div>
  )
}

export default async function OverviewPage() {
  const roster = await getTodayRoster()

  const present = roster.filter(s => s.status === 'present')
  const late    = roster.filter(s => s.status === 'late')
  const notHere = roster.filter(s => !s.status)
  const absent  = roster.filter(s => s.status === 'absent')

  const dayLabel = new Intl.DateTimeFormat('en-SG', {
    timeZone: 'Asia/Singapore',
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(new Date())

  return (
    <>
      <AutoRefresh intervalMs={30000} />

      <div className="max-w-7xl mx-auto space-y-6">
        <PageHeader title="Overview" subtitle={dayLabel} />

        {roster.length === 0 ? (
          <div className="bg-white rounded-3xl p-12 text-center shadow-card">
            <p className="text-sm text-muted-foreground">
              No students expected today — open the kiosk to create sessions.
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <Column
              title="Present"
              count={present.length}
              students={present}
              emptyText="No one marked on time yet"
              accent="text-emerald-700"
            />
            <Column
              title="Late"
              count={late.length}
              students={late}
              emptyText="No late arrivals"
              accent="text-amber-600"
            />
            <Column
              title="Not here yet"
              count={notHere.length}
              students={notHere}
              emptyText="Everyone has signed in"
              accent="text-muted-foreground"
            />
          </div>
        )}

        {absent.length > 0 && (
          <div>
            <OtherSection title="Absent" students={absent} accent="text-rose-600" />
          </div>
        )}
      </div>
    </>
  )
}

function OtherSection({
  title,
  students,
  accent,
}: {
  title: string
  students: StudentTodayEntry[]
  accent: string
}) {
  if (students.length === 0) return null
  return (
    <div>
      <p className={`text-[0.7rem] font-bold uppercase tracking-[0.05em] mb-3 ${accent}`}>
        {title} · {students.length}
      </p>
      <div className="space-y-3">
        {students.map(s => (
          <div
            key={s.studentId}
            className="flex items-center gap-3 bg-white rounded-[1.25rem] p-4 shadow-card"
          >
            <Avatar name={s.fullName} size="sm" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{s.fullName}</p>
              <p className="text-xs text-muted-foreground truncate">{s.classNames.join(' · ')}</p>
            </div>
            <StatusBadge status={s.status} />
          </div>
        ))}
      </div>
    </div>
  )
}
