import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { getMobileSession } from '@/lib/mobile-queries'
import { RosterClient } from '@/components/mobile/roster-client'

export const dynamic = 'force-dynamic'

export default async function MobileSessionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const result = await getMobileSession(id)
  if (!result) notFound()
  return (
    <div className="space-y-4">
      <Link href={`/mobile/classes/${result.classInfo.id}`} className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> {result.classInfo.name}</Link>
      <section>
        <p className="text-xs font-black uppercase tracking-[.15em] text-brand/60">{result.session.sessionDate}</p>
        <h1 className="font-display text-3xl font-semibold text-brand-ink">Class register</h1>
        <p className="mt-1 text-sm text-muted-foreground">Tap P, L, A, or E to mark each student.</p>
      </section>
      <RosterClient sessionId={id} initialRoster={result.roster} initialNotes={result.session.notes ?? ''} ended={Boolean(result.session.endedAt)} />
    </div>
  )
}
