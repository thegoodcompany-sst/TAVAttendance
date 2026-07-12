import { cn } from '@/lib/utils'
import type { SessionSummary } from '@/lib/queries'
import { SessionNote } from './session-note'

// TAVA-toned bands: navy, bright blue, and marigold accents.
const GRADIENTS = [
  'from-blue-500 via-indigo-600 to-[#193775]',
  'from-sky-400 via-blue-500 to-indigo-600',
  'from-amber-300 via-[#FAC12F] to-orange-400',
  'from-indigo-400 via-blue-500 to-[#193775]',
  'from-[#FAC12F] via-amber-400 to-orange-500',
]

export function ClassTile({
  session,
  index,
  showNotes = false,
}: {
  session: SessionSummary
  index: number
  showNotes?: boolean
}) {
  return (
    <div className="rounded-3xl overflow-hidden bg-white shadow-card">
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
        {showNotes && <SessionNote sessionId={session.sessionId} note={session.notes} />}
      </div>
    </div>
  )
}
