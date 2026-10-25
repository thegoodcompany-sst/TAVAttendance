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
  const attempt = useRef<{
    file: File
    path: string
    token: string
    uploaded: boolean
    recoveryRequired: boolean
    editMetadata: boolean
    upload: Parameters<typeof finalizeResultSlipUpload>[1]
  } | null>(null)
  const [recoveryRequired, setRecoveryRequired] = useState(false)
  const [metadataLocked, setMetadataLocked] = useState(false)
  const [hasAttempt, setHasAttempt] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    const file = formData.get('file')
    startTransition(async () => {
      if (!attempt.current && (!(file instanceof File) || file.size === 0)) {
        setError('A file is required.')
        return
      }
      if (!attempt.current && file instanceof File && !ALLOWED_TYPES.has(file.type)) {
        setError('File must be a PDF, JPG, or PNG.')
        return
      }
      if (!attempt.current && file instanceof File && file.size > MAX_BYTES) {
        setError('File must be under 10MB.')
        return
      }

      try {
        if (!attempt.current && file instanceof File) {
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

          attempt.current = {
            file, path: prepared.path, token: prepared.token, uploaded: false, editMetadata: false, recoveryRequired: false,
            upload: {
              path: prepared.path, fileType: file.type, fileSize: file.size,
              examName: String(formData.get('exam_name') ?? ''),
              subject: String(formData.get('subject') ?? '') || null,
              score: optionalNumber(formData, 'score'),
              maxScore: optionalNumber(formData, 'max_score'),
            },
          }
        }
        setHasAttempt(true)
        const current = attempt.current
        if (!current) return
        if (current.editMetadata) {
          current.upload = {
            ...current.upload,
            examName: String(formData.get('exam_name') ?? ''),
            subject: String(formData.get('subject') ?? '') || null,
            score: optionalNumber(formData, 'score'),
            maxScore: optionalNumber(formData, 'max_score'),
          }
          current.editMetadata = false
        }
        setMetadataLocked(true)
        if (!current.uploaded) {
          const supabase = createClient()
          const { error: uploadError } = await supabase.storage
            .from('result-slips')
            .uploadToSignedUrl(current.path, current.token, current.file, {
              contentType: current.file.type,
            })
          // A previous upload may have succeeded even if its response was lost.
          // A duplicate is only a reason to try trusted verification, never proof
          // that the stored contents are valid.
          const alreadyPresent = uploadError && (
            uploadError.statusCode === '409' ||
            ('code' in uploadError && uploadError.code === 'ResourceAlreadyExists') ||
            uploadError.message === 'The resource already exists' ||
            uploadError.message === 'Resource already exists'
          )
          if (uploadError && !alreadyPresent) {
            setError('Could not upload the file. Please try again.')
            return
          }

          current.uploaded = true
        }

        const wasAmbiguous = current.recoveryRequired
        // A thrown/lost action response may conceal a commit too.
        current.recoveryRequired = true
        setRecoveryRequired(true)
        const result = await finalizeResultSlipUpload(studentId, current.upload)
        const { error } = result
        if (error) {
          // Validation of the unchanged payload proves it could never finalize.
          current.recoveryRequired = result.kind !== 'validation' && (wasAmbiguous || result.kind === 'ambiguous')
          setRecoveryRequired(current.recoveryRequired)
          current.editMetadata = !current.recoveryRequired && result.kind === 'validation'
          setMetadataLocked(!current.editMetadata)
          setError(error)
        } else {
          setRecoveryRequired(false)
          attempt.current = null
          setHasAttempt(false)
          setMetadataLocked(false)
          formRef.current?.reset()
          router.refresh()
        }
      } catch {
        setError('Could not complete the upload. Please try again to resume it.')
      }
    })
  }

  const inputClass =
    'w-full rounded-lg border border-input bg-white px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20'

  return (
    <form ref={formRef} onSubmit={handleSubmit} className="space-y-3">
      <fieldset disabled={isPending || metadataLocked} className="space-y-3">
        <input name="exam_name" placeholder="Exam name (e.g. Mid-Year Maths)" required className={inputClass} />
        <div className="flex gap-3">
          <input name="subject" placeholder="Subject (optional)" className={inputClass} />
          <input name="score" type="number" step="any" placeholder="Score" className={inputClass} />
          <input name="max_score" type="number" step="any" placeholder="Out of" className={inputClass} />
        </div>
      </fieldset>
      <input name="file" type="file" accept="application/pdf,image/jpeg,image/png" required disabled={isPending || hasAttempt} className="block text-sm" />
      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={isPending}
          className="inline-flex items-center gap-1 text-sm font-medium text-primary-foreground bg-primary hover:bg-primary/80 px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50"
        >
          {isPending ? 'Uploading…' : recoveryRequired ? 'Retry recovery' : 'Upload slip'}
        </button>
        {hasAttempt && !recoveryRequired && (
          <button
            type="button"
            disabled={isPending}
            onClick={() => {
              attempt.current = null
              setHasAttempt(false)
              setMetadataLocked(false)
              setError(null)
              const fileInput = formRef.current?.elements.namedItem('file')
              if (fileInput instanceof HTMLInputElement) fileInput.value = ''
            }}
            className="text-sm font-medium text-primary disabled:opacity-50"
          >
            Start over / change file
          </button>
        )}
        {error && <p className="text-xs text-destructive">{error}</p>}
      </div>
    </form>
  )
}
