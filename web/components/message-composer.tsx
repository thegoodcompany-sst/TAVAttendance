'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'

export function MessageComposer({
  studentId,
  recipientId,
  action,
}: {
  studentId: string
  recipientId?: string
  action: (studentId: string, subject: string, body: string, recipientId?: string) => Promise<{ error: string | null }>
}) {
  const router = useRouter()
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handleSend = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await action(studentId, subject, body, recipientId)
      if (error) setError(error)
      else {
        setSubject('')
        setBody('')
        router.refresh()
      }
    })
  }

  return (
    <div className="space-y-2">
      <input
        value={subject}
        onChange={e => setSubject(e.target.value)}
        placeholder="Subject (optional)"
        className="w-full rounded-lg border border-input bg-white px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20"
      />
      <textarea
        value={body}
        onChange={e => setBody(e.target.value)}
        placeholder="Write a message…"
        rows={3}
        className="w-full rounded-lg border border-input bg-white px-3 py-2 text-sm focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20"
      />
      <div className="flex items-center gap-3">
        <button
          onClick={handleSend}
          disabled={isPending || !body.trim()}
          className="inline-flex items-center gap-1 text-sm font-medium text-primary-foreground bg-primary hover:bg-primary/80 px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50"
        >
          {isPending ? 'Sending…' : 'Send'}
        </button>
        {error && <p className="text-xs text-destructive">{error}</p>}
      </div>
    </div>
  )
}
