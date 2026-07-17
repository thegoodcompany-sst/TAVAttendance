'use client'

import { useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { uploadResultSlip } from '@/app/actions/parent-portal'

export function UploadForm({ studentId }: { studentId: string }) {
  const router = useRouter()
  const formRef = useRef<HTMLFormElement>(null)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    startTransition(async () => {
      const { error } = await uploadResultSlip(studentId, formData)
      if (error) setError(error)
      else {
        formRef.current?.reset()
        router.refresh()
      }
    })
  }

  const inputClass =
    'w-full rounded-lg border border-input bg-white px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20'

  return (
    <form ref={formRef} onSubmit={handleSubmit} className="space-y-3">
      <input name="exam_name" placeholder="Exam name (e.g. Mid-Year Maths)" required className={inputClass} />
      <div className="flex gap-3">
        <input name="subject" placeholder="Subject (optional)" className={inputClass} />
        <input name="score" type="number" step="any" placeholder="Score" className={inputClass} />
        <input name="max_score" type="number" step="any" placeholder="Out of" className={inputClass} />
      </div>
      <input name="file" type="file" accept="application/pdf,image/jpeg,image/png" required className="block text-sm" />
      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={isPending}
          className="inline-flex items-center gap-1 text-sm font-medium text-primary-foreground bg-primary hover:bg-primary/80 px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50"
        >
          {isPending ? 'Uploading…' : 'Upload slip'}
        </button>
        {error && <p className="text-xs text-destructive">{error}</p>}
      </div>
    </form>
  )
}
