import { cn } from '@/lib/utils'
import { formatScheduleTime } from '@/lib/date'
import type { SessionSummary } from '@/lib/queries'

const BG_GRADIENTS = [
  'from-blue-500 to-[#193775]',
  'from-sky-400 to-indigo-600',
  'from-[#FAC12F] to-orange-500',
  'from-indigo-400 to-[#193775]',
  'from-amber-400 to-orange-600',
]

function classInitials(name: string) {
  return name
    .split(' ')
    .map(w => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase()
}

export function ScheduleList({ sessions }: { sessions: SessionSummary[] }) {
  if (sessions.length === 0) {
    return (
      <p className="text-sm text-muted-foreground text-center py-8">
        No sessions today
      </p>
    )
  }

  return (
    <div className="space-y-4">
      {sessions.map((s, i) => (
        <div key={s.sessionId} className="flex items-center gap-3">
          <div
            className={cn(
              'w-10 h-10 rounded-xl bg-gradient-to-br flex items-center justify-center text-white text-xs font-bold flex-shrink-0',
              BG_GRADIENTS[i % BG_GRADIENTS.length]
            )}
          >
            {classInitials(s.className)}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium truncate">{s.className}</p>
            <p className="text-xs text-muted-foreground">
              {s.scheduleTime ? formatScheduleTime(s.scheduleTime) : '—'}
            </p>
          </div>
          <span className="text-xs font-semibold text-brand-ink bg-brand-soft rounded-full px-2.5 py-1 flex-shrink-0">
            {s.presentCount + s.lateCount}/{s.totalEnrolled}
          </span>
        </div>
      ))}
    </div>
  )
}
