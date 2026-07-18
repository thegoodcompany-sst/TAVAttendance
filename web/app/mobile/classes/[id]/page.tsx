import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft, CalendarDays, CheckCircle2, Clock3 } from 'lucide-react'
import { getMobileClass } from '@/lib/mobile-queries'
import { todayInTz } from '@/lib/date'
import { ClassActionButton } from '@/components/mobile/start-class-button'
import { createClient } from '@/lib/supabase/server'
import { DeactivateClassButton } from '@/components/mobile/deactivate-class-button'

export const dynamic = 'force-dynamic'

export default async function MobileClassPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [result, { data: profile }] = await Promise.all([
    getMobileClass(id),
    supabase.from('profiles').select('role').eq('id', user!.id).single(),
  ])
  if (!result) notFound()
  const { classInfo, sessions } = result
  const today = todayInTz()
  const todaySession = sessions.find(session => session.sessionDate === today)
  return (
    <div className="space-y-5">
      <Link href="/mobile/classes" className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> Classes</Link>
      <section className="overflow-hidden rounded-[2rem] bg-brand text-white shadow-[0_18px_40px_rgba(25,55,117,.22)]">
        <div className="p-6">
          <p className="text-xs font-black uppercase tracking-[.15em] text-blue-200">{[classInfo.subject, classInfo.level].filter(Boolean).join(' · ') || 'Class'}</p>
          <h1 className="mt-1 font-display text-3xl font-semibold leading-tight">{classInfo.name}</h1>
          <div className="mt-5 flex gap-4 text-sm text-blue-100">
            <span className="flex items-center gap-1.5"><CalendarDays size={16} />{classInfo.scheduleDay || 'Flexible'}</span>
            <span className="flex items-center gap-1.5"><Clock3 size={16} />{classInfo.scheduleTime?.slice(0, 5) || 'No time'}</span>
          </div>
        </div>
        <div className="bg-white/10 p-4">
          {!todaySession ? <ClassActionButton classId={id} mode="start" /> : todaySession.endedAt ? <ClassActionButton classId={id} sessionId={todaySession.id} mode="resume" /> : todaySession.startedAt ? (
            <Link href={`/mobile/sessions/${todaySession.id}`} className="flex min-h-13 items-center justify-center gap-2 rounded-2xl bg-accent-marigold px-4 text-sm font-black text-brand-ink"><CheckCircle2 size={19} /> Return to today&apos;s roster</Link>
          ) : <ClassActionButton classId={id} mode="start" />}
        </div>
      </section>

      {profile?.role === 'admin' && <div className="space-y-3"><div className="grid grid-cols-2 gap-3"><Link href={`/mobile/classes/${id}/students`} className="flex min-h-12 items-center justify-center rounded-2xl border border-brand/15 bg-white text-sm font-black text-brand shadow-card">Manage students</Link><Link href={`/mobile/classes/${id}/edit`} className="flex min-h-12 items-center justify-center rounded-2xl border border-brand/15 bg-white text-sm font-black text-brand shadow-card">Edit class</Link></div><DeactivateClassButton classId={id} className={classInfo.name} /></div>}

      <section>
        <h2 className="mb-3 text-xs font-black uppercase tracking-[.14em] text-brand/60">Session register</h2>
        {sessions.length === 0 ? <div className="rounded-[1.5rem] bg-white p-7 text-center text-sm text-muted-foreground shadow-card">No sessions yet.</div> : (
          <div className="overflow-hidden rounded-[1.5rem] border border-brand/10 bg-white shadow-card">
            {sessions.map((session) => (
              <Link key={session.id} href={`/mobile/sessions/${session.id}`} className="flex min-h-16 items-center gap-3 border-b border-brand/8 px-4 last:border-0 hover:bg-brand-soft/40">
                <span className="font-mono text-sm font-bold text-brand">{session.sessionDate}</span>
                <span className="flex-1 text-sm text-muted-foreground">{session.endedAt ? 'Ended' : session.startedAt ? 'In progress' : 'Not started'}</span>
                <span className={session.endedAt ? 'h-2.5 w-2.5 rounded-full bg-slate-300' : 'h-2.5 w-2.5 rounded-full bg-emerald-500'} />
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
