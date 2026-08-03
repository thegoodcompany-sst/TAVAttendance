'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { removeUser } from '@/app/actions/invite'
import { Trash2, Loader2 } from 'lucide-react'

export function RemoveUserButton({ userId, name }: { userId: string; name: string }) {
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  const handleRemove = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await removeUser(userId)
      if (error) {
        setError(error)
        setConfirming(false)
      } else {
        router.refresh()
      }
    })
  }

  if (error) {
    return <span className="text-xs text-destructive">{error}</span>
  }

  if (confirming) {
    return (
      <div className="flex items-center gap-1.5">
        <span className="text-xs text-muted-foreground hidden sm:inline">Remove {name.split(' ')[0]}?</span>
        <button
          onClick={handleRemove}
          disabled={isPending}
          className="text-xs font-medium text-destructive hover:text-destructive/80 transition-colors flex items-center gap-1 disabled:opacity-50"
        >
          {isPending ? <Loader2 size={12} className="animate-spin" /> : null}
          {isPending ? 'Removing…' : 'Yes, remove'}
        </button>
        <span className="text-muted-foreground text-xs">·</span>
        <button
          onClick={() => setConfirming(false)}
          className="text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          Cancel
        </button>
      </div>
    )
  }

  return (
    <button
      type="button"
      onClick={() => setConfirming(true)}
      className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium text-muted-foreground hover:text-destructive hover:bg-destructive/8 transition-colors"
      title={`Remove ${name}`}
      aria-label={`Remove ${name}`}
    >
      <Trash2 size={14} />
      <span>Remove</span>
    </button>
  )
}
