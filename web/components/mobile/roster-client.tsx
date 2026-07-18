'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Check, Clock3, FileText, Search, UserX, X } from 'lucide-react'
import { endClass, markAttendance, markRemainingAbsent, reopenClass, saveMobileSessionNote } from '@/app/actions/mobile'
import type { AttendanceStatus } from '@/lib/status'
import type { MobileRosterEntry } from '@/lib/mobile-queries'

const statuses: { value: Exclude<AttendanceStatus, null>; short: string; label: string; className: string }[] = [
  { value: 'present', short: 'P', label: 'Present', className: 'border-emerald-200 bg-emerald-50 text-emerald-700 data-[selected=true]:border-emerald-600 data-[selected=true]:bg-emerald-600 data-[selected=true]:text-white' },
  { value: 'late', short: 'L', label: 'Late', className: 'border-amber-200 bg-amber-50 text-amber-700 data-[selected=true]:border-amber-500 data-[selected=true]:bg-amber-500 data-[selected=true]:text-brand-ink' },
  { value: 'absent', short: 'A', label: 'Absent', className: 'border-red-200 bg-red-50 text-red-700 data-[selected=true]:border-red-600 data-[selected=true]:bg-red-600 data-[selected=true]:text-white' },
  { value: 'excused', short: 'E', label: 'Excused', className: 'border-slate-200 bg-slate-50 text-slate-600 data-[selected=true]:border-slate-500 data-[selected=true]:bg-slate-500 data-[selected=true]:text-white' },
]

function markedTime(value: string | null) {
  if (!value) return null
  return new Intl.DateTimeFormat('en-SG', { timeZone: 'Asia/Singapore', hour: 'numeric', minute: '2-digit' }).format(new Date(value))
}

export function RosterClient({ sessionId, initialRoster, initialNotes, ended }: { sessionId: string; initialRoster: MobileRosterEntry[]; initialNotes: string; ended: boolean }) {
  const router = useRouter()
  const [roster, setRoster] = useState(initialRoster)
  const [query, setQuery] = useState('')
  const [notes, setNotes] = useState(initialNotes)
  const [showNotes, setShowNotes] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busyIds, setBusyIds] = useState<Set<string>>(new Set())
  const [isPending, startTransition] = useTransition()
  const unmarked = roster.filter(entry => !entry.status)
  const filtered = useMemo(() => roster.filter(entry => entry.fullName.toLowerCase().includes(query.toLowerCase())), [roster, query])

  function updateStatus(entry: MobileRosterEntry, status: Exclude<AttendanceStatus, null>) {
    if (ended) return
    const previous = entry.status
    const now = new Date().toISOString()
    setError(null)
    setRoster(current => current.map(row => row.studentId === entry.studentId ? { ...row, status, markedAt: now } : row))
    setBusyIds(current => new Set(current).add(entry.studentId))
    startTransition(async () => {
      const result = await markAttendance(sessionId, entry.studentId, status)
      setBusyIds(current => { const next = new Set(current); next.delete(entry.studentId); return next })
      if (result.error) {
        setRoster(current => current.map(row => row.studentId === entry.studentId ? { ...row, status: previous } : row))
        setError(result.error)
      }
    })
  }

  function markRest() {
    if (!window.confirm(`Mark ${unmarked.length} remaining student${unmarked.length === 1 ? '' : 's'} absent?`)) return
    const ids = unmarked.map(entry => entry.studentId)
    const now = new Date().toISOString()
    setRoster(current => current.map(row => ids.includes(row.studentId) ? { ...row, status: 'absent', markedAt: now } : row))
    startTransition(async () => {
      const result = await markRemainingAbsent(sessionId, ids)
      if (result.error) setError(result.error)
    })
  }

  function toggleEnded() {
    if (!ended && !window.confirm('End class? Attendance changes will be locked until the class is resumed.')) return
    startTransition(async () => {
      const result = ended ? await reopenClass(sessionId) : await endClass(sessionId)
      if (result.error) setError(result.error)
      else router.refresh()
    })
  }

  function saveNotes() {
    startTransition(async () => {
      const result = await saveMobileSessionNote(sessionId, notes)
      if (result.error) setError(result.error)
      else setShowNotes(false)
    })
  }

  const counts = Object.fromEntries(statuses.map(status => [status.value, roster.filter(row => row.status === status.value).length]))

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-5 overflow-hidden rounded-2xl border border-brand/10 bg-white shadow-card">
        {statuses.map(status => <div key={status.value} className="border-r border-brand/8 px-1 py-3 text-center last:border-0"><p className="font-mono text-xl font-black text-brand-ink">{counts[status.value]}</p><p className="text-[9px] font-black uppercase tracking-wide text-muted-foreground">{status.label}</p></div>)}
        <div className="px-1 py-3 text-center"><p className="font-mono text-xl font-black text-brand-ink">{unmarked.length}</p><p className="text-[9px] font-black uppercase tracking-wide text-muted-foreground">Unmarked</p></div>
      </div>

      <div className="flex gap-2">
        <label className="flex min-h-12 flex-1 items-center gap-2 rounded-2xl border border-brand/10 bg-white px-3 shadow-card focus-within:ring-2 focus-within:ring-brand/20">
          <Search size={18} className="text-brand/50" />
          <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Find a student" className="min-w-0 flex-1 bg-transparent text-base outline-none placeholder:text-muted-foreground" />
          {query && <button onClick={() => setQuery('')} aria-label="Clear search"><X size={17} /></button>}
        </label>
        <button type="button" onClick={() => setShowNotes(true)} aria-label="Session notes" className="grid h-12 w-12 place-items-center rounded-2xl border border-brand/10 bg-white text-brand shadow-card"><FileText size={19} /></button>
      </div>

      {error && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
      {ended && <div className="rounded-2xl border border-slate-200 bg-slate-100 px-4 py-3 text-sm font-bold text-slate-700">This class has ended. Resume it to change attendance.</div>}

      <div className="space-y-2.5">
        {filtered.map(entry => (
          <article key={entry.studentId} className="rounded-[1.4rem] border border-brand/10 bg-white p-4 shadow-card">
            <div className="mb-3 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <h2 className="truncate text-base font-black text-brand-ink">{entry.fullName}</h2>
                <p className="flex h-4 items-center gap-1 text-[11px] font-bold text-muted-foreground">{busyIds.has(entry.studentId) ? <><Clock3 size={11} /> Saving…</> : markedTime(entry.markedAt) ? `Marked ${markedTime(entry.markedAt)}` : 'Not marked yet'}</p>
              </div>
              {entry.status && <Check size={18} className="text-emerald-600" />}
            </div>
            <div className="grid grid-cols-4 gap-2">
              {statuses.map(status => (
                <button
                  key={status.value}
                  type="button"
                  title={status.label}
                  aria-label={`Mark ${entry.fullName} ${status.label}`}
                  data-selected={entry.status === status.value}
                  disabled={ended || busyIds.has(entry.studentId)}
                  onClick={() => updateStatus(entry, status.value)}
                  className={`min-h-11 rounded-xl border text-sm font-black transition-transform active:scale-95 disabled:opacity-55 ${status.className}`}
                >{status.short}</button>
              ))}
            </div>
          </article>
        ))}
      </div>

      {!ended && unmarked.length > 0 && <button type="button" onClick={markRest} disabled={isPending} className="flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl border border-red-200 bg-red-50 text-sm font-black text-red-700"><UserX size={18} /> Mark {unmarked.length} remaining absent</button>}
      <button type="button" onClick={toggleEnded} disabled={isPending} className={ended ? 'min-h-12 w-full rounded-2xl bg-brand text-sm font-black text-white' : 'min-h-12 w-full rounded-2xl border border-slate-200 bg-white text-sm font-black text-slate-700'}>{isPending ? 'Working…' : ended ? 'Resume class' : 'End class'}</button>

      {showNotes && <div className="fixed inset-0 z-50 flex items-end bg-brand/35 p-3 backdrop-blur-sm" onMouseDown={event => { if (event.target === event.currentTarget) setShowNotes(false) }}>
        <div className="mx-auto w-full max-w-lg rounded-[2rem] bg-white p-5 shadow-2xl">
          <div className="mb-4 flex items-center justify-between"><h2 className="font-display text-2xl font-semibold text-brand-ink">Session notes</h2><button onClick={() => setShowNotes(false)} className="grid h-10 w-10 place-items-center rounded-full bg-muted"><X size={19} /></button></div>
          <textarea value={notes} onChange={event => setNotes(event.target.value)} rows={6} className="w-full rounded-2xl border border-input p-3 text-base outline-none focus:ring-2 focus:ring-brand/20" placeholder="Notes for staff. Do not include NRIC/FIN." />
          <button onClick={saveNotes} disabled={isPending} className="mt-3 min-h-12 w-full rounded-2xl bg-brand text-sm font-black text-white">{isPending ? 'Saving…' : 'Save notes'}</button>
        </div>
      </div>}
    </div>
  )
}
