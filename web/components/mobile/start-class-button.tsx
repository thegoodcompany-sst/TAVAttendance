'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Eye, Play, Square } from 'lucide-react'
import { endClass, startTodayClass } from '@/app/actions/mobile'

type Mode = 'start' | 'view' | 'end'

export function ClassActionButton({ classId, sessionId, mode }: { classId: string; sessionId?: string; mode: Mode }) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const label = mode === 'end' ? 'End class' : mode === 'view' ? 'View ended class' : "Start today's class"
  const Icon = mode === 'end' ? Square : mode === 'view' ? Eye : Play

  function run() {
    if (mode === 'view') {
      router.push(`/mobile/sessions/${sessionId}`)
      return
    }
    if (mode === 'end' && !window.confirm('End this class? Attendance will be permanently locked.')) return
    setError(null)
    startTransition(async () => {
      const result = mode === 'start'
        ? await startTodayClass(classId)
        : await endClass(sessionId!)
      if (result.error) return setError(result.error)
      if (mode === 'start' && 'sessionId' in result && result.sessionId) router.push(`/mobile/sessions/${result.sessionId}`)
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
