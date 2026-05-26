import { cn } from '@/lib/utils'
import type { SessionSummary } from '@/lib/queries'

const GRADIENTS = [
  'from-violet-300 via-purple-400 to-fuchsia-500',
  'from-blue-300 via-indigo-400 to-violet-500',
  'from-emerald-300 via-teal-400 to-cyan-500',
  'from-amber-300 via-orange-400 to-rose-400',
  'from-rose-300 via-pink-400 to-fuchsia-500',
]

export function ClassTile({
  session,
  index,
}: {
  session: SessionSummary
  index: number
}) {
  return (
    <div className="rounded-3xl overflow-hidden bg-white shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
      <div
        className={cn(
          'h-28 bg-gradient-to-br',
          GRADIENTS[index % GRADIENTS.length]
        )}
      />
      <div className="p-4">
        <p className="font-semibold text-sm">{session.className}</p>
        <p className="text-xs text-muted-foreground mt-1">
          {session.presentCount + session.lateCount} of {session.totalEnrolled} here today
        </p>
      </div>
    </div>
  )
}
