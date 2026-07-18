'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { ChevronRight, Search, X } from 'lucide-react'
import type { StudentRow, StudentResult } from '@/lib/queries'

export function MobileStudentList({ students, results }: { students: StudentRow[]; results: StudentResult[] }) {
  const [query, setQuery] = useState('')
  const filtered = useMemo(() => students.filter(student => `${student.fullName} ${student.school ?? ''} ${student.yearOfStudy ?? ''}`.toLowerCase().includes(query.toLowerCase())), [students, query])
  const grades = new Map<string, StudentResult[]>()
  for (const result of results) grades.set(result.studentId, [...(grades.get(result.studentId) ?? []), result])
  return <>
    <label className="flex min-h-12 items-center gap-2 rounded-2xl border border-brand/10 bg-white px-3 shadow-card focus-within:ring-2 focus-within:ring-brand/20"><Search size={18} className="text-brand/50" /><input value={query} onChange={event => setQuery(event.target.value)} className="min-w-0 flex-1 bg-transparent text-base outline-none" placeholder="Search students" />{query && <button onClick={() => setQuery('')} aria-label="Clear"><X size={17} /></button>}</label>
    <div className="mt-4 overflow-hidden rounded-[1.5rem] border border-brand/10 bg-white shadow-card">
      {filtered.map(student => <Link key={student.id} href={`/mobile/students/${student.id}`} className="flex min-h-[4.6rem] items-center gap-3 border-b border-brand/8 px-4 last:border-0 active:bg-brand-soft/60">
        <div className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-brand-soft font-display font-bold text-brand-ink">{student.fullName.split(/\s+/).slice(0, 2).map(part => part[0]).join('').toUpperCase()}</div>
        <div className="min-w-0 flex-1"><p className="truncate font-black text-brand-ink">{student.fullName}</p><p className="truncate text-xs text-muted-foreground">{grades.get(student.id)?.map(result => `${result.subject} ${result.grade}`).join(' · ') || [student.school, student.yearOfStudy].filter(Boolean).join(' · ') || 'No details'}</p></div><ChevronRight size={20} className="text-brand/25" />
      </Link>)}
      {filtered.length === 0 && <p className="p-8 text-center text-sm text-muted-foreground">No students match that search.</p>}
    </div>
  </>
}
