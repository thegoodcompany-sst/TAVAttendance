import Link from 'next/link'
import { CalendarDays, ChevronRight, Clock3, Plus } from 'lucide-react'
import { getMobileClasses } from '@/lib/mobile-queries'
import { createClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'

function displayTime(value: string | null) {
  if (!value) return 'Time not set'
  const [hour, minute] = value.split(':').map(Number)
  const suffix = hour >= 12 ? 'PM' : 'AM'
  return `${hour % 12 || 12}:${String(minute).padStart(2, '0')} ${suffix}`
}

export default async function MobileClassesPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [classes, { data: profile }] = await Promise.all([
    getMobileClasses(),
    supabase.from('profiles').select('role').eq('id', user!.id).single(),
  ])
  return (
    <div className="space-y-5">
      <section className="flex items-end justify-between gap-4">
        <div>
          <p className="text-xs font-black uppercase tracking-[.16em] text-brand/60">Teaching floor</p>
          <h1 className="font-display text-3xl font-semibold text-brand-ink">Your classes</h1>
          <p className="mt-1 text-sm text-muted-foreground">Open a class to take attendance.</p>
        </div>
        {profile?.role === 'admin' && <Link href="/mobile/classes/new" aria-label="Add class" className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-accent-marigold text-accent-marigold-foreground shadow-card">
          <Plus size={22} />
        </Link>}
      </section>

      {classes.length === 0 ? (
        <div className="rounded-[1.75rem] border border-brand/10 bg-white p-8 text-center shadow-card">
          <p className="font-bold">No classes available</p>
          <p className="mt-1 text-sm text-muted-foreground">Admins can add a class; tutors only see assigned classes.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {classes.map((cls, index) => (
            <Link key={cls.id} href={`/mobile/classes/${cls.id}`} className="group block rounded-[1.75rem] border border-brand/10 bg-white p-5 shadow-card transition-transform active:scale-[.99]">
              <div className="flex items-start gap-4">
                <div className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-brand-soft font-mono text-sm font-black text-brand-ink">{String(index + 1).padStart(2, '0')}</div>
                <div className="min-w-0 flex-1">
                  <h2 className="font-display text-xl font-semibold leading-tight text-brand-ink">{cls.name}</h2>
                  <p className="mt-1 text-sm text-muted-foreground">{[cls.subject, cls.level].filter(Boolean).join(' · ') || 'General class'}</p>
                  <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs font-bold text-brand/70">
                    <span className="flex items-center gap-1.5"><CalendarDays size={14} />{cls.scheduleDay || 'Flexible day'}</span>
                    <span className="flex items-center gap-1.5"><Clock3 size={14} />{displayTime(cls.scheduleTime)}</span>
                  </div>
                </div>
                <ChevronRight className="mt-2 text-brand/30 transition-transform group-hover:translate-x-1" size={22} />
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
