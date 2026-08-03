import type { SessionSummary } from '@/lib/queries/attendance'
import { formatScheduleTime } from '@/lib/date'
import { SessionNote } from './session-note'

export function ClassTile({
  session,
  showNotes = false,
}: {
  session: SessionSummary
  showNotes?: boolean
}) {
  const hereCount = session.presentCount + session.lateCount
  const attendanceRate = session.totalEnrolled > 0
    ? Math.round((hereCount / session.totalEnrolled) * 100)
    : 0

  const parts: string[] = []
  if (session.scheduleTime) {
    parts.push(`Starts ${formatScheduleTime(session.scheduleTime)}`)
  }
  if (session.presentCount > 0) parts.push(`${session.presentCount} present`)
  if (session.lateCount > 0) parts.push(`${session.lateCount} late`)
  if (session.notHereCount > 0) parts.push(`${session.notHereCount} not here yet`)
  if (session.absentCount > 0) parts.push(`${session.absentCount} absent`)
  if (parts.length === 0 || (parts.length === 1 && session.scheduleTime)) {
    parts.push(`${session.totalEnrolled} expected`)
  }

  return (
    <div className="grid gap-3 border-t border-brand/20 py-4 sm:grid-cols-[minmax(0,1fr)_8rem_5rem] sm:items-start sm:gap-6">
      <div className="min-w-0">
        <p className="text-sm font-bold text-foreground">{session.className}</p>
        <p className="mt-0.5 text-xs text-muted-foreground">{parts.join(' · ')}</p>
        <div className="mt-3 h-1 overflow-hidden rounded-full bg-brand/10" aria-hidden="true">
          <div className="h-full rounded-full bg-brand" style={{ width: `${attendanceRate}%` }} />
        </div>
        {showNotes && (
          <div className="mt-2">
            <SessionNote sessionId={session.sessionId} note={session.notes} />
          </div>
        )}
      </div>
      <p className="font-mono text-sm font-semibold tabular-nums text-brand-ink sm:pt-0.5 sm:text-right">
        {attendanceRate}%
      </p>
      <p className="text-left text-xs font-bold text-brand sm:text-right">
        {hereCount}
        <span className="text-muted-foreground">/{session.totalEnrolled}</span>
      </p>
    </div>
  )
}
