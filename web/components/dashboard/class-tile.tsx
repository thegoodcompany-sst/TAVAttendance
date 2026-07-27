import type { SessionSummary } from '@/lib/queries'
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

  return (
    <div className="grid gap-3 border-t border-brand/20 py-4 sm:grid-cols-[minmax(0,1fr)_8rem_5rem] sm:items-start sm:gap-6">
      <div className="min-w-0">
        <p className="text-sm font-bold text-foreground">{session.className}</p>
        {showNotes && <SessionNote sessionId={session.sessionId} note={session.notes} />}
      </div>
      <div>
        <div className="mb-1.5 flex items-center justify-between text-[11px] text-muted-foreground">
          <span>Here</span>
          <span className="font-mono tabular-nums">{attendanceRate}%</span>
        </div>
        <div className="h-1 bg-brand/10" aria-hidden="true">
          <div className="h-full bg-brand" style={{ width: `${attendanceRate}%` }} />
        </div>
      </div>
      <p className="font-mono text-sm font-semibold tabular-nums text-brand-ink sm:text-right">
        {hereCount}
        <span className="text-muted-foreground">/{session.totalEnrolled}</span>
      </p>
    </div>
  )
}
