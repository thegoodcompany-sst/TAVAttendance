'use client'

import { useState, useTransition } from 'react'
import { NotebookPen, Loader2 } from 'lucide-react'
import { updateSessionNote } from '@/app/actions/sessions'

export function SessionNote({
  sessionId,
  note,
}: {
  sessionId: string
  note: string | null
}) {
  const [editing, setEditing] = useState(false)
  const [value, setValue] = useState(note ?? '')
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const save = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await updateSessionNote(sessionId, value)
      if (error) setError(error)
      else setEditing(false)
    })
  }

  if (!editing) {
    return (
      <button
        onClick={() => setEditing(true)}
        className="mt-2 flex items-start gap-1.5 text-left text-xs text-muted-foreground hover:text-foreground transition-colors w-full"
      >
        <NotebookPen size={13} className="flex-shrink-0 mt-0.5" />
        <span className="min-w-0">{note?.trim() || 'Add a session note'}</span>
      </button>
    )
  }

  return (
    <div className="mt-2 space-y-2">
      <textarea
        value={value}
        onChange={e => setValue(e.target.value)}
        rows={3}
        autoFocus
        placeholder="Session note…"
        className="w-full text-xs rounded-lg border border-border bg-background p-2 outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
      />
      <div className="flex items-center gap-3">
        <button
          onClick={save}
          disabled={isPending}
          className="inline-flex items-center gap-1 text-xs font-medium text-brand-ink hover:text-brand transition-colors disabled:opacity-50"
        >
          {isPending && <Loader2 size={12} className="animate-spin" />}
          Save
        </button>
        <button
          onClick={() => { setValue(note ?? ''); setEditing(false); setError(null) }}
          className="text-xs text-muted-foreground hover:text-foreground"
        >
          Cancel
        </button>
      </div>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
