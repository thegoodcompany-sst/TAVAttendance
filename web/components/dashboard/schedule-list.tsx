import { formatScheduleTime } from '@/lib/date'
import type { SessionSummary } from '@/lib/queries/attendance'

export function ScheduleList({ sessions }: { sessions: SessionSummary[] }) {
  if (sessions.length === 0) {
    return (
      <div className="border-y border-brand/15 py-6">
        <p className="text-sm text-muted-foreground">No sessions today</p>
      </div>
    )
  }

  return (
    <div className="border-t border-brand/15">
      {sessions.map(s => (
        <div key={s.sessionId} className="grid grid-cols-[4.5rem_minmax(0,1fr)_auto] items-center gap-3 border-b border-brand/15 py-3">
          <time className="font-mono text-xs font-medium tabular-nums text-brand-ink">
            {s.scheduleTime ? formatScheduleTime(s.scheduleTime) : '—'}
          </time>
          <div className="min-w-0">
            <p className="truncate text-sm font-bold text-foreground">{s.className}</p>
            <p className="mt-0.5 text-[11px] text-muted-foreground">
              {s.totalEnrolled} enrolled
              {s.presentCount + s.lateCount > 0
                ? ` · ${s.presentCount + s.lateCount} here`
                : ''}
            </p>
          </div>
          <p className="text-right font-mono text-sm font-semibold tabular-nums text-brand-ink">
            {s.presentCount + s.lateCount}
            <span className="text-muted-foreground">/{s.totalEnrolled}</span>
          </p>
        </div>
      ))}
    </div>
  )
}
