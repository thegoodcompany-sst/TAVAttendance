'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Search, UserCheck, X } from 'lucide-react'
import { markKioskAttendance, prepareSignInBoard, signInKioskStudent } from '@/app/actions/mobile'
import type { KioskEntry } from '@/lib/mobile-queries'
import type { AttendanceStatus } from '@/lib/status'

const style: Record<string, string> = {
  present: 'border-emerald-300 bg-emerald-50 text-emerald-800',
  late: 'border-amber-300 bg-amber-50 text-amber-900',
  absent: 'border-red-300 bg-red-50 text-red-800',
  excused: 'border-slate-200 bg-white text-brand-ink',
  unmarked: 'border-brand/10 bg-white text-brand-ink',
}

export function SignInBoard({ initialEntries }: { initialEntries: KioskEntry[] }) {
  const router = useRouter()
  const [entries, setEntries] = useState(initialEntries)
  const [query, setQuery] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<Set<string>>(new Set())
  const [isPending, startTransition] = useTransition()
  const filtered = useMemo(() => entries.filter(entry => entry.fullName.toLowerCase().includes(query.toLowerCase())), [entries, query])

  function prepare() {
    startTransition(async () => {
      const result = await prepareSignInBoard()
      if (result.error) setError(result.error)
      else router.refresh()
    })
  }

  function mark(entry: KioskEntry, status: Exclude<AttendanceStatus, null>) {
    const previous = entry.status
    setEntries(current => current.map(row => row.studentId === entry.studentId ? { ...row, status, markedAt: new Date().toISOString() } : row))
    setBusy(current => new Set(current).add(entry.studentId))
    startTransition(async () => {
      const result = await markKioskAttendance(entry.sessionIds, entry.studentId, status)
      setBusy(current => { const next = new Set(current); next.delete(entry.studentId); return next })
      if (result.error) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? { ...row, status: previous } : row))
        setError(result.error)
      }
    })
  }

  function signIn(entry: KioskEntry) {
    if (entry.status === 'present') return mark(entry, 'excused')
    const previous = entry.status
    setEntries(current => current.map(row => row.studentId === entry.studentId ? { ...row, status: 'present', markedAt: new Date().toISOString() } : row))
    setBusy(current => new Set(current).add(entry.studentId))
    startTransition(async () => {
      const result = await signInKioskStudent(entry.sessionIds, entry.studentId)
      setBusy(current => { const next = new Set(current); next.delete(entry.studentId); return next })
      if (result.error) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? { ...row, status: previous } : row))
        setError(result.error)
      } else if (result.status) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? { ...row, status: result.status! } : row))
      }
    })
  }

  return <div className="space-y-4">
    <button onClick={prepare} disabled={isPending} className="flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl bg-accent-marigold text-sm font-black text-brand-ink shadow-card"><UserCheck size={18} />{isPending ? 'Preparing…' : "Prepare today's sign-in board"}</button>
    <label className="flex min-h-12 items-center gap-2 rounded-2xl border border-brand/10 bg-white px-3 shadow-card"><Search size={18} className="text-brand/50"/><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Find a student" className="min-w-0 flex-1 bg-transparent text-base outline-none" />{query && <button onClick={() => setQuery('')}><X size={17}/></button>}</label>
    {error && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
    <div className="grid grid-cols-2 gap-3">{filtered.map(entry => <article key={entry.studentId} className={`min-h-36 rounded-[1.5rem] border p-4 shadow-card ${style[entry.status ?? 'unmarked']}`}>
      <button type="button" disabled={busy.has(entry.studentId)} onClick={() => signIn(entry)} className="flex h-full w-full flex-col text-left disabled:opacity-60">
        <p className="font-display text-lg font-semibold leading-tight">{entry.fullName}</p><p className="mt-1 line-clamp-2 text-[11px] font-bold opacity-65">{entry.classNames.join(' · ')}</p><span className="mt-auto rounded-full bg-current/10 px-2 py-1 text-[10px] font-black uppercase tracking-wide">{busy.has(entry.studentId) ? 'Saving' : entry.status === 'present' ? 'On time' : entry.status === 'late' ? 'Late' : entry.status === 'absent' ? 'Absent' : 'Tap to sign in'}</span>
      </button>
      <div className="mt-2 grid grid-cols-3 gap-1 border-t border-current/10 pt-2">{(['late','absent','excused'] as const).map(status => <button key={status} onClick={() => mark(entry, status)} aria-label={`Mark ${entry.fullName} ${status}`} className="min-h-8 rounded-lg bg-white/65 text-[10px] font-black uppercase">{status === 'excused' ? 'Not here' : status}</button>)}</div>
    </article>)}</div>
    {entries.length === 0 && <div className="rounded-[1.5rem] bg-white p-8 text-center shadow-card"><p className="font-bold">No sign-in cards yet</p><p className="mt-1 text-sm text-muted-foreground">Prepare the board to create today&apos;s scheduled sessions.</p></div>}
  </div>
}
