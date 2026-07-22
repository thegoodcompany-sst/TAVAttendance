import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { getMobileSession } from '@/lib/mobile-queries'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { todayInTz } from '@/lib/date'
import { RosterClient } from '@/components/mobile/roster-client'

export const dynamic = 'force-dynamic'

export default async function MobileSessionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const [result, notesEnabled] = await Promise.all([
    getMobileSession(id),
    isFeatureEnabled('session_notes'),
  ])
  if (!result) notFound()
  const readOnly = Boolean(result.session.endedAt)
    || result.session.sessionDate !== todayInTz()
    || !result.classInfo.canOperateTodaySession
  return (
    <div className="space-y-4">
      <Link href={`/mobile/classes/${result.classInfo.id}`} className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> {result.classInfo.name}</Link>
      <section>
        <p className="text-xs font-black uppercase tracking-[.15em] text-brand/60">{result.session.sessionDate}</p>
        <h1 className="font-display text-3xl font-semibold text-brand-ink">Class register</h1>
        <p className="mt-1 text-sm text-muted-foreground">{readOnly ? 'Review this register in read-only mode.' : 'Tap P, L, A, or E to mark each student.'}</p>
      </section>
      <RosterClient
        sessionId={id}
        initialRoster={result.roster}
        initialNotes={notesEnabled ? (result.session.notes ?? '') : ''}
        readOnly={readOnly}
        notesEnabled={notesEnabled}
      />
    </div>
  )
}
