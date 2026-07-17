'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Check } from 'lucide-react'
import { acknowledgeSlip } from '@/app/actions/result-slips'

export function AcknowledgeButton({ id }: { id: string }) {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handleClick = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await acknowledgeSlip(id)
      if (error) setError(error)
      else router.refresh()
    })
  }

  return (
    <div className="flex-shrink-0 text-right">
      <button
        onClick={handleClick}
        disabled={isPending}
        className="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 bg-emerald-50 hover:bg-emerald-100 px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50"
      >
        <Check size={13} /> Acknowledge
      </button>
      {error && <p className="mt-1 text-xs text-destructive">{error}</p>}
    </div>
  )
}
