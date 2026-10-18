'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { resetDemoMode } from '@/app/actions/demo'

/** Small "Demo" pill with a reset control. Rendered only in demo mode. */
export function DemoBadge({ tone = 'light' }: { tone?: 'light' | 'dark' }) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [confirming, setConfirming] = useState(false)

  const reset = () => {
    startTransition(async () => {
      await resetDemoMode()
      setConfirming(false)
      router.refresh()
    })
  }

  const pill = tone === 'dark'
    ? 'bg-amber-300/20 text-amber-100 ring-amber-200/40'
    : 'bg-amber-100 text-amber-800 ring-amber-300'

  return (
    <div className="flex items-center gap-1.5" data-testid="demo-badge">
      <span
        className={`rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide ring-1 ${pill}`}
        title="Demo mode: invented data, stored only on this device. Nothing is saved to TAVA."
      >
        Demo
      </span>
      {confirming ? (
        <span className="flex items-center gap-1 text-xs">
          <button
            type="button"
            onClick={reset}
            disabled={pending}
            className="rounded-md bg-amber-500 px-2 py-0.5 font-medium text-white hover:bg-amber-600 disabled:opacity-60"
          >
            {pending ? 'Resetting…' : 'Reset'}
          </button>
          <button
            type="button"
            onClick={() => setConfirming(false)}
            className={tone === 'dark' ? 'text-blue-100 hover:text-white' : 'text-muted-foreground hover:text-foreground'}
          >
            Cancel
          </button>
        </span>
      ) : (
        <button
          type="button"
          onClick={() => setConfirming(true)}
          className={`text-xs underline-offset-2 hover:underline ${tone === 'dark' ? 'text-blue-100 hover:text-white' : 'text-muted-foreground hover:text-foreground'}`}
        >
          Reset demo
        </button>
      )}
    </div>
  )
}
