'use client'

import { useMemo, useState, useTransition } from 'react'
import { Search } from 'lucide-react'
import { setClassEnrollment } from '@/app/actions/mobile'

type Student = { id: string; fullName: string; school: string | null; yearOfStudy: string | null }

export function EnrollmentList({ classId, students, initialEnrolledIds }: { classId: string; students: Student[]; initialEnrolledIds: string[] }) {
  const [query, setQuery] = useState('')
  const [enrolled, setEnrolled] = useState(new Set(initialEnrolledIds))
  const [busy, setBusy] = useState(new Set<string>())
  const [error, setError] = useState<string | null>(null)
  const [, startTransition] = useTransition()
  const filtered = useMemo(() => students.filter(student => student.fullName.toLowerCase().includes(query.toLowerCase())), [students, query])

  function toggle(studentId: string) {
    const nextValue = !enrolled.has(studentId)
    setEnrolled(current => { const next = new Set(current); if (nextValue) next.add(studentId); else next.delete(studentId); return next })
    setBusy(current => new Set(current).add(studentId))
    startTransition(async () => {
      const result = await setClassEnrollment(classId, studentId, nextValue)
      setBusy(current => { const next = new Set(current); next.delete(studentId); return next })
      if (result.error) {
        setError(result.error)
        setEnrolled(current => { const next = new Set(current); if (!nextValue) next.add(studentId); else next.delete(studentId); return next })
      }
    })
  }

  return <div className="space-y-4">
    <div className="rounded-2xl bg-brand-soft px-4 py-3 text-sm font-bold text-brand-ink">{enrolled.size} student{enrolled.size === 1 ? '' : 's'} enrolled</div>
    <label className="flex min-h-12 items-center gap-2 rounded-2xl border border-brand/10 bg-white px-3 shadow-card"><Search size={18} className="text-brand/50" /><input value={query} onChange={event => setQuery(event.target.value)} className="min-w-0 flex-1 bg-transparent text-base outline-none" placeholder="Find a student" /></label>
    {error && <p role="alert" className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
    <div className="overflow-hidden rounded-[1.5rem] border border-brand/10 bg-white shadow-card">{filtered.map(student => <label key={student.id} className="flex min-h-16 cursor-pointer items-center gap-3 border-b border-brand/8 px-4 last:border-0"><input type="checkbox" checked={enrolled.has(student.id)} disabled={busy.has(student.id)} onChange={() => toggle(student.id)} className="h-5 w-5 accent-brand" /><span className="min-w-0 flex-1"><span className="block truncate font-bold text-brand-ink">{student.fullName}</span><span className="block truncate text-xs text-muted-foreground">{[student.school, student.yearOfStudy].filter(Boolean).join(' · ') || 'No details'}</span></span>{busy.has(student.id) && <span className="text-xs font-bold text-muted-foreground">Saving…</span>}</label>)}</div>
  </div>
}
