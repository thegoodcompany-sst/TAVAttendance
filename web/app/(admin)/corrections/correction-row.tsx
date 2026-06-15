'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Check, X, ArrowRight } from 'lucide-react'
import { applyCorrection, rejectCorrection } from '@/app/actions/corrections'
import type { PendingCorrection } from '@/lib/queries'

export function CorrectionRow({ request }: { request: PendingCorrection }) {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [rejecting, setRejecting] = useState(false)
  const [reviewNote, setReviewNote] = useState('')
  const [isPending, startTransition] = useTransition()

  const handleApply = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await applyCorrection(request.id)
      if (error) setError(error)
      else router.refresh()
    })
  }

  const handleReject = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await rejectCorrection(request.id, reviewNote)
      if (error) setError(error)
      else router.refresh()
    })
  }

  return (
    <div className="bg-white rounded-2xl p-5 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="font-semibold text-sm">{request.studentName}</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Field: <code className="bg-muted px-1 py-0.5 rounded">{request.fieldName}</code>
          </p>
          <div className="mt-2 flex items-center gap-2 text-sm flex-wrap">
            <span className="text-muted-foreground line-through">{request.currentValue || '—'}</span>
            <ArrowRight size={13} className="text-muted-foreground" />
            <span className="font-medium text-brand-ink">{request.requestedValue || '—'}</span>
          </div>
        </div>
        {!rejecting && (
          <div className="flex items-center gap-2 flex-shrink-0">
            <button
              onClick={handleApply}
              disabled={isPending}
              className="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 bg-emerald-50 hover:bg-emerald-100 px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50"
            >
              <Check size={13} /> Apply
            </button>
            <button
              onClick={() => setRejecting(true)}
              disabled={isPending}
              className="inline-flex items-center gap-1 text-xs font-medium text-destructive bg-destructive/8 hover:bg-destructive/15 px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50"
            >
              <X size={13} /> Reject
            </button>
          </div>
        )}
      </div>

      {rejecting && (
        <div className="mt-4 space-y-2">
          <input
            value={reviewNote}
            onChange={e => setReviewNote(e.target.value)}
            placeholder="Reason for rejection (optional)"
            className="w-full rounded-lg border border-input bg-white px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20"
          />
          <div className="flex items-center gap-2">
            <button
              onClick={handleReject}
              disabled={isPending}
              className="text-xs font-medium text-destructive hover:text-destructive/80 disabled:opacity-50"
            >
              {isPending ? 'Rejecting…' : 'Confirm reject'}
            </button>
            <span className="text-muted-foreground text-xs">·</span>
            <button
              onClick={() => setRejecting(false)}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {error && <p className="mt-3 text-xs text-destructive">{error}</p>}
    </div>
  )
}
