'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { deactivateStudent, deleteStudentResult, saveStudentResult, updateStudent } from '@/app/actions/mobile'

const grades = ['AL1','AL2','AL3','AL4','AL5','AL6','AL7','AL8','A1','A2','B3','B4','C5','C6','D7','E8','F9']
const field = 'min-h-12 w-full rounded-2xl border border-input bg-white px-3 text-base outline-none focus:ring-2 focus:ring-brand/20'

export function StudentDetailActions({ student, initialResults, isAdmin }: {
  student: { id: string; full_name: string; school: string | null; year_of_study: string | null; notes: string | null }
  initialResults: { subject: 'Math' | 'English'; grade: string }[]
  isAdmin: boolean
}) {
  const router = useRouter()
  const [editing, setEditing] = useState(false)
  const [fullName, setFullName] = useState(student.full_name)
  const [school, setSchool] = useState(student.school ?? '')
  const [yearOfStudy, setYearOfStudy] = useState(student.year_of_study ?? '')
  const [notes, setNotes] = useState(student.notes ?? '')
  const [results, setResults] = useState(new Map(initialResults.map(result => [result.subject, result.grade])))
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  function saveStudent() {
    startTransition(async () => {
      const result = await updateStudent(student.id, { fullName, school, yearOfStudy, notes })
      if (result.error) return setError(result.error)
      setEditing(false)
      router.refresh()
    })
  }

  function changeGrade(subject: 'Math' | 'English', grade: string) {
    const before = results.get(subject)
    setResults(current => new Map(current).set(subject, grade))
    startTransition(async () => {
      const result = grade ? await saveStudentResult(student.id, subject, grade) : await deleteStudentResult(student.id, subject)
      if (result.error) {
        setError(result.error)
        setResults(current => { const next = new Map(current); if (before) next.set(subject, before); else next.delete(subject); return next })
      }
    })
  }

  function deactivate() {
    if (!window.confirm(`Deactivate ${student.full_name}? Their attendance history will be preserved.`)) return
    startTransition(async () => {
      const result = await deactivateStudent(student.id)
      if (result.error) return setError(result.error)
      router.push('/mobile/students')
      router.refresh()
    })
  }

  return <div className="space-y-4">
    <section className="rounded-[1.5rem] border border-brand/10 bg-white p-5 shadow-card">
      <div className="mb-4"><p className="text-xs font-black uppercase tracking-[.14em] text-brand/60">Current grades</p><p className="mt-1 text-sm text-muted-foreground">Changes save immediately.</p></div>
      <div className="grid grid-cols-2 gap-3">{(['Math', 'English'] as const).map(subject => <label key={subject} className="space-y-1.5"><span className="text-sm font-bold">{subject}</span><select value={results.get(subject) ?? ''} onChange={event => changeGrade(subject, event.target.value)} disabled={isPending} className={field}><option value="">No grade</option>{grades.map(grade => <option key={grade}>{grade}</option>)}</select></label>)}</div>
    </section>

    {isAdmin && <section className="rounded-[1.5rem] border border-brand/10 bg-white p-5 shadow-card">
      {!editing ? <div className="flex gap-2"><button onClick={() => setEditing(true)} className="min-h-12 flex-1 rounded-2xl bg-brand text-sm font-black text-white">Edit student</button><button onClick={deactivate} disabled={isPending} className="min-h-12 rounded-2xl border border-red-200 bg-red-50 px-4 text-sm font-black text-red-700">Deactivate</button></div> : <div className="space-y-3">
        <label className="block space-y-1"><span className="text-sm font-bold">Full name</span><input value={fullName} onChange={event => setFullName(event.target.value)} className={field} /></label>
        <div className="grid grid-cols-2 gap-3"><label className="space-y-1"><span className="text-sm font-bold">School</span><input value={school} onChange={event => setSchool(event.target.value)} className={field} /></label><label className="space-y-1"><span className="text-sm font-bold">Year</span><input value={yearOfStudy} onChange={event => setYearOfStudy(event.target.value)} className={field} /></label></div>
        <label className="block space-y-1"><span className="text-sm font-bold">Notes</span><textarea value={notes} onChange={event => setNotes(event.target.value)} rows={3} className={`${field} py-3`} /><span className="text-xs text-muted-foreground">Do not include NRIC/FIN.</span></label>
        <div className="flex gap-2"><button onClick={() => setEditing(false)} className="min-h-12 flex-1 rounded-2xl border border-input text-sm font-black">Cancel</button><button onClick={saveStudent} disabled={isPending} className="min-h-12 flex-1 rounded-2xl bg-brand text-sm font-black text-white">{isPending ? 'Saving…' : 'Save'}</button></div>
      </div>}
    </section>}
    {error && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
  </div>
}
