'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { UserPlus } from 'lucide-react'
import { createStudent } from '@/app/actions/students'
import { Button } from '@/components/ui/button'
import { NricWarning } from '@/components/nric-warning'

const inputClass =
  'w-full rounded-lg border border-input bg-white px-3 py-2.5 text-sm shadow-xs focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20 transition-shadow'

export function NewStudentForm() {
  const router = useRouter()
  const [fullName, setFullName] = useState('')
  const [dateOfBirth, setDateOfBirth] = useState('')
  const [school, setSchool] = useState('')
  const [yearOfStudy, setYearOfStudy] = useState('')
  const [notes, setNotes] = useState('')
  const [consent, setConsent] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    startTransition(async () => {
      const { error } = await createStudent(
        {
          fullName,
          dateOfBirth: dateOfBirth || null,
          school,
          yearOfStudy,
          notes,
        },
        consent
      )
      if (error) {
        setError(error)
      } else {
        router.push('/students')
        router.refresh()
      }
    })
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <div className="space-y-1.5">
        <label className="text-sm font-medium" htmlFor="fullName">Full name</label>
        <input id="fullName" required value={fullName} onChange={e => setFullName(e.target.value)} className={inputClass} placeholder="e.g. Tan Wei Lin" />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="space-y-1.5">
          <label className="text-sm font-medium" htmlFor="dob">Date of birth</label>
          <input id="dob" type="date" value={dateOfBirth} onChange={e => setDateOfBirth(e.target.value)} className={inputClass} />
        </div>
        <div className="space-y-1.5">
          <label className="text-sm font-medium" htmlFor="year">Year of study</label>
          <input id="year" value={yearOfStudy} onChange={e => setYearOfStudy(e.target.value)} className={inputClass} placeholder="e.g. Sec 2" />
        </div>
      </div>

      <div className="space-y-1.5">
        <label className="text-sm font-medium" htmlFor="school">School</label>
        <input id="school" value={school} onChange={e => setSchool(e.target.value)} className={inputClass} placeholder="e.g. Raffles Institution" />
      </div>

      <div className="space-y-1.5">
        <label className="text-sm font-medium" htmlFor="notes">Notes</label>
        <textarea id="notes" rows={3} value={notes} onChange={e => setNotes(e.target.value)} className={inputClass} placeholder="Optional" />
        <NricWarning />
      </div>

      {/* Consent attestation gate */}
      <label className="flex items-start gap-3 rounded-xl border border-border bg-surface px-4 py-3 cursor-pointer">
        <input
          type="checkbox"
          checked={consent}
          onChange={e => setConsent(e.target.checked)}
          className="mt-0.5 h-4 w-4 rounded border-input accent-brand"
        />
        <span className="text-sm text-foreground">
          Parent/guardian consent obtained for collection of this child&apos;s data.
        </span>
      </label>

      {error && (
        <p className="text-sm text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-3 py-2.5">
          {error}
        </p>
      )}

      <Button type="submit" className="w-full gap-2" disabled={isPending || !consent}>
        <UserPlus size={15} />
        {isPending ? 'Saving…' : 'Add student'}
      </Button>
    </form>
  )
}
