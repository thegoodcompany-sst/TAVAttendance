'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { deactivateClass } from '@/app/actions/mobile'

export function DeactivateClassButton({ classId, className }: { classId: string; className: string }) {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  function run() {
    if (!window.confirm(`Hide ${className}? Its sessions and attendance history will be preserved.`)) return
    startTransition(async () => {
      const result = await deactivateClass(classId)
      if (result.error) return setError(result.error)
      router.push('/mobile/classes')
      router.refresh()
    })
  }
  return <div><button type="button" onClick={run} disabled={isPending} className="min-h-12 w-full rounded-2xl border border-red-200 bg-red-50 text-sm font-black text-red-700">{isPending ? 'Hiding…' : 'Deactivate class'}</button>{error && <p role="alert" className="mt-2 text-sm text-red-700">{error}</p>}</div>
}
