'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Search, UserCheck, X } from 'lucide-react'
import { clearKioskAttendance, markKioskAttendance, prepareSignInBoard, signInKioskStudent } from '@/app/actions/mobile'
import type { KioskEntry } from '@/lib/mobile-queries'
import { statusLabel, type AttendanceStatus } from '@/lib/status'

const style: Record<string, string> = {
  present: 'border-emerald-300 bg-emerald-50 text-emerald-800',
  late: 'border-amber-300 bg-amber-50 text-amber-900',
  absent: 'border-red-300 bg-red-50 text-red-800',
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

  function mark(
    entry: KioskEntry,
    status: Exclude<AttendanceStatus, null>,
    absenceInformed: boolean | null = null,
  ) {
    const previous = entry.status
    const previousInformed = entry.absenceInformed
    setEntries(current => current.map(row => row.studentId === entry.studentId ? {
      ...row,
      status,
      absenceInformed: status === 'absent' ? absenceInformed : null,
      markedAt: new Date().toISOString(),
    } : row))
    setBusy(current => new Set(current).add(entry.studentId))
    startTransition(async () => {
      const result = await markKioskAttendance(entry.sessionIds, entry.studentId, status, absenceInformed)
      setBusy(current => { const next = new Set(current); next.delete(entry.studentId); return next })
      if (result.error) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? {
          ...row,
          status: previous,
          absenceInformed: previousInformed,
        } : row))
        setError(result.error)
      }
    })
  }

  function clear(entry: KioskEntry) {
    const previous = entry.status
    const previousMarkedAt = entry.markedAt
    const previousInformed = entry.absenceInformed
    setEntries(current => current.map(row => row.studentId === entry.studentId ? {
      ...row,
      status: null,
      absenceInformed: null,
      markedAt: null,
    } : row))
    setBusy(current => new Set(current).add(entry.studentId))
    startTransition(async () => {
      const result = await clearKioskAttendance(entry.sessionIds, entry.studentId)
      setBusy(current => { const next = new Set(current); next.delete(entry.studentId); return next })
      if (result.error) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? {
          ...row,
          status: previous,
          absenceInformed: previousInformed,
          markedAt: previousMarkedAt,
        } : row))
        setError(result.error)
      }
    })
  }

  function signIn(entry: KioskEntry) {
    if (entry.status === 'present') return clear(entry)
    const previous = entry.status
    const previousInformed = entry.absenceInformed
    setEntries(current => current.map(row => row.studentId === entry.studentId ? {
      ...row,
      status: 'present',
      absenceInformed: null,
      markedAt: new Date().toISOString(),
    } : row))
    setBusy(current => new Set(current).add(entry.studentId))
    startTransition(async () => {
      const result = await signInKioskStudent(entry.sessionIds, entry.studentId)
      setBusy(current => { const next = new Set(current); next.delete(entry.studentId); return next })
      if (result.error) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? {
          ...row,
          status: previous,
          absenceInformed: previousInformed,
        } : row))
        setError(result.error)
      } else if (result.status) {
        setEntries(current => current.map(row => row.studentId === entry.studentId ? {
          ...row,
          status: result.status!,
          absenceInformed: null,
        } : row))
      }
    })
  }

  return <div className="space-y-4">
    <button onClick={prepare} disabled={isPending} className="flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl bg-accent-marigold text-sm font-black text-brand-ink shadow-card"><UserCheck size={18} />{isPending ? 'Preparing…' : "Prepare today's sign-in board"}</button>
    <label className="flex min-h-12 items-center gap-2 rounded-2xl border border-brand/10 bg-white px-3 shadow-card"><Search size={18} className="text-brand/50"/><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Find a student" className="min-w-0 flex-1 bg-transparent text-base outline-none" />{query && <button onClick={() => setQuery('')}><X size={17}/></button>}</label>
    {error && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
    <div className="grid grid-cols-2 gap-3">{filtered.map(entry => <article key={entry.studentId} className={`min-h-36 rounded-[1.5rem] border p-4 shadow-card ${style[entry.status ?? 'unmarked']}`}>
      <button type="button" disabled={busy.has(entry.studentId)} onClick={() => signIn(entry)} className="flex h-full w-full flex-col text-left disabled:opacity-60">
        <p className="font-display text-lg font-semibold leading-tight">{entry.fullName}</p>
        <p className="mt-1 line-clamp-2 text-[11px] font-bold opacity-65">{entry.classNames.join(' · ')}</p>
        <span className="mt-auto rounded-full bg-current/10 px-2 py-1 text-[10px] font-black uppercase tracking-wide">
          {busy.has(entry.studentId) ? 'Saving' : statusLabel(entry.status, entry.absenceInformed) === 'Not here yet' ? 'Tap to sign in' : statusLabel(entry.status, entry.absenceInformed)}
        </span>
      </button>
      <div className="mt-2 grid grid-cols-2 gap-1 border-t border-current/10 pt-2">
        <button onClick={() => mark(entry, 'late')} aria-label={`Mark ${entry.fullName} late`} className="min-h-8 rounded-lg bg-white/65 text-[10px] font-black uppercase">Late</button>
        <button onClick={() => clear(entry)} aria-label={`Mark ${entry.fullName} not here yet`} className="min-h-8 rounded-lg bg-white/65 text-[10px] font-black uppercase">Not here yet</button>
        <button onClick={() => mark(entry, 'absent', true)} aria-label={`Mark ${entry.fullName} absent informed`} className="min-h-8 rounded-lg bg-white/65 text-[10px] font-black uppercase">Informed</button>
        <button onClick={() => mark(entry, 'absent', false)} aria-label={`Mark ${entry.fullName} absent no notice`} className="min-h-8 rounded-lg bg-white/65 text-[10px] font-black uppercase">No notice</button>
      </div>
    </article>)}</div>
    {entries.length === 0 && <div className="rounded-[1.5rem] bg-white p-8 text-center shadow-card"><p className="font-bold">No sign-in cards yet</p><p className="mt-1 text-sm text-muted-foreground">Prepare the board to create today&apos;s scheduled sessions.</p></div>}
  </div>
}
