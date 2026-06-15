'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Upload, CheckCircle2 } from 'lucide-react'
import { bulkImportStudents, type BulkImportResult } from '@/app/actions/students'
import { parseStudentCsv } from '@/lib/csv'
import { Button } from '@/components/ui/button'
import { NricWarning } from '@/components/nric-warning'

const inputClass =
  'w-full rounded-lg border border-input bg-white px-3 py-2.5 text-sm font-mono shadow-xs focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20 transition-shadow'

export function ImportForm() {
  const router = useRouter()
  const [text, setText] = useState('')
  const [consent, setConsent] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<BulkImportResult | null>(null)
  const [isPending, startTransition] = useTransition()

  const parsed = useMemo(() => parseStudentCsv(text), [text])

  const handleImport = () => {
    setError(null)
    setResult(null)
    if (parsed.length === 0) {
      setError('No rows to import.')
      return
    }
    startTransition(async () => {
      const res = await bulkImportStudents(
        parsed.map(r => ({
          fullName: r.fullName,
          dateOfBirth: r.dateOfBirth,
          school: r.school,
          yearOfStudy: r.yearOfStudy,
          notes: r.notes,
        })),
        consent
      )
      if (res.error) {
        setError(res.error)
      } else {
        setResult(res)
        router.refresh()
      }
    })
  }

  return (
    <div className="space-y-5">
      <div className="space-y-1.5">
        <label className="text-sm font-medium" htmlFor="csv">CSV rows</label>
        <textarea
          id="csv"
          rows={8}
          value={text}
          onChange={e => setText(e.target.value)}
          className={inputClass}
          placeholder={'full_name, date_of_birth, school, year_of_study, notes\nTan Wei Lin,2010-04-12,Raffles,Sec 2,'}
        />
        <div className="flex items-center justify-between">
          <NricWarning />
          <span className="text-xs text-muted-foreground">{parsed.length} row{parsed.length !== 1 ? 's' : ''} detected</span>
        </div>
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
          Parent/guardian consent has been obtained for all students in this import.
        </span>
      </label>

      {error && (
        <p className="text-sm text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-3 py-2.5">
          {error}
        </p>
      )}

      {result && (
        <div className="text-sm bg-brand-soft border border-brand/20 rounded-lg px-3 py-2.5 space-y-1.5">
          <p className="flex items-center gap-2 text-brand-ink font-medium">
            <CheckCircle2 size={14} />
            Imported {result.created} student{result.created !== 1 ? 's' : ''}.
          </p>
          {result.skipped.length > 0 && (
            <ul className="text-xs text-muted-foreground list-disc pl-5">
              {result.skipped.map(s => (
                <li key={s.row}>Row {s.row} skipped: {s.reason}</li>
              ))}
            </ul>
          )}
        </div>
      )}

      <Button onClick={handleImport} className="w-full gap-2" disabled={isPending || !consent || parsed.length === 0}>
        <Upload size={15} />
        {isPending ? 'Importing…' : `Import ${parsed.length || ''} student${parsed.length !== 1 ? 's' : ''}`.trim()}
      </Button>
    </div>
  )
}
