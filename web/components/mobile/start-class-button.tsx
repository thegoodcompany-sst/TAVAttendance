'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Play, RotateCcw, Square } from 'lucide-react'
import { endClass, reopenClass, startTodayClass } from '@/app/actions/mobile'

type Mode = 'start' | 'resume' | 'end'

export function ClassActionButton({ classId, sessionId, mode }: { classId: string; sessionId?: string; mode: Mode }) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const label = mode === 'end' ? 'End class' : mode === 'resume' ? 'Resume class' : "Start today's class"
  const Icon = mode === 'end' ? Square : mode === 'resume' ? RotateCcw : Play

  function run() {
    if (mode === 'end' && !window.confirm('End this class? Attendance can no longer be changed until it is resumed.')) return
    setError(null)
    startTransition(async () => {
      const result = mode === 'start'
        ? await startTodayClass(classId)
        : mode === 'resume'
          ? await reopenClass(sessionId!)
          : await endClass(sessionId!)
      if (result.error) return setError(result.error)
      if (mode === 'start' && 'sessionId' in result && result.sessionId) router.push(`/mobile/sessions/${result.sessionId}`)
      else if (mode === 'resume') router.push(`/mobile/sessions/${sessionId}`)
      else router.refresh()
    })
  }

  return (
    <div>
      <button
        type="button"
        onClick={run}
        disabled={isPending}
        className={mode === 'end'
          ? 'flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 text-sm font-bold text-red-700 disabled:opacity-60'
          : 'flex min-h-13 w-full items-center justify-center gap-2 rounded-2xl bg-brand px-4 text-sm font-bold text-white shadow-[0_8px_20px_rgba(25,55,117,.22)] disabled:opacity-60'}
      >
        <Icon size={18} fill={mode === 'start' ? 'currentColor' : 'none'} />
        {isPending ? 'Working…' : label}
      </button>
      {error && <p role="alert" className="mt-2 text-sm text-red-700">{error}</p>}
    </div>
  )
}
