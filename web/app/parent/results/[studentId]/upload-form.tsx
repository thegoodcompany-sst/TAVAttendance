'use client'

import { useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  finalizeResultSlipUpload,
  prepareResultSlipUpload,
} from '@/app/actions/parent-portal'
import { createClient } from '@/lib/supabase/client'

const ALLOWED_TYPES = new Set(['application/pdf', 'image/jpeg', 'image/png'])
const MAX_BYTES = 10 * 1024 * 1024

function optionalNumber(formData: FormData, name: string): number | null {
  const raw = String(formData.get(name) ?? '').trim()
  return raw ? Number(raw) : null
}

export function UploadForm({ studentId }: { studentId: string }) {
  const router = useRouter()
  const formRef = useRef<HTMLFormElement>(null)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    const file = formData.get('file')
    startTransition(async () => {
      if (!(file instanceof File) || file.size === 0) {
        setError('A file is required.')
        return
      }
      if (!ALLOWED_TYPES.has(file.type)) {
        setError('File must be a PDF, JPG, or PNG.')
        return
      }
      if (file.size > MAX_BYTES) {
        setError('File must be under 10MB.')
        return
      }

      const prepared = await prepareResultSlipUpload(
        studentId,
        file.name,
        file.type,
        file.size,
      )
      if (prepared.error || !prepared.path || !prepared.token) {
        setError(prepared.error ?? 'Could not prepare the upload.')
        return
      }

      const supabase = createClient()
      const { error: uploadError } = await supabase.storage
        .from('result-slips')
        .uploadToSignedUrl(prepared.path, prepared.token, file, {
          contentType: file.type,
        })
      if (uploadError) {
        setError('Could not upload the file. Please try again.')
        return
      }

      const { error } = await finalizeResultSlipUpload(studentId, {
        path: prepared.path,
        fileType: file.type,
        fileSize: file.size,
        examName: String(formData.get('exam_name') ?? ''),
        subject: String(formData.get('subject') ?? '') || null,
        score: optionalNumber(formData, 'score'),
        maxScore: optionalNumber(formData, 'max_score'),
      })
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
