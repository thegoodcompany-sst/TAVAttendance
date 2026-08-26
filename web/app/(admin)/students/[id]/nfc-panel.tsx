'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { CreditCard, Loader2 } from 'lucide-react'
import { pairNfcChip, revokeNfcChip } from '@/app/actions/nfc'
import type { StudentNfcBinding } from '@/lib/queries/nfc'

export function NfcPanel({
  studentId,
  studentName,
  binding,
}: {
  studentId: string
  studentName: string
  binding: StudentNfcBinding | null
}) {
  const router = useRouter()
  const [uid, setUid] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const handlePair = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await pairNfcChip(studentId, uid)
      if (error) {
        setError(error)
        return
      }
      setUid('')
      router.refresh()
    })
  }

  const handleRevoke = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await revokeNfcChip(studentId)
      if (error) setError(error)
      else router.refresh()
    })
  }

  return (
    <div className="bg-white rounded-3xl p-6 shadow-card space-y-4">
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
        Arrival card
      </p>
      <p className="text-sm text-muted-foreground">
        Pair the chip UID shown on the station when {studentName} taps an unknown card.
        The website keeps the last four characters only.
      </p>

      {binding ? (
        <p className="text-sm">
          Active card ending <span className="font-mono font-semibold">…{binding.chipUidSuffix}</span>
          <span className="text-muted-foreground">
            {' '}· issued {new Date(binding.issuedAt).toLocaleDateString('en-SG', { timeZone: 'Asia/Singapore' })}
          </span>
        </p>
      ) : (
        <p className="text-sm text-muted-foreground">No active card.</p>
      )}

      <div className="flex flex-col sm:flex-row gap-2">
        <input
          value={uid}
          onChange={e => setUid(e.target.value)}
          placeholder="Chip UID (from the station screen)"
          autoComplete="off"
          spellCheck={false}
          className="flex-1 rounded-lg border border-border px-3 py-2 text-sm font-mono shadow-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/40"
        />
        <button
          type="button"
          onClick={handlePair}
          disabled={isPending || uid.trim() === ''}
          className="inline-flex items-center justify-center gap-1.5 text-sm font-medium bg-brand text-white px-3 py-2 rounded-lg disabled:opacity-50"
        >
          {isPending ? <Loader2 size={14} className="animate-spin" /> : <CreditCard size={14} />}
          {binding ? 'Reissue' : 'Pair'}
        </button>
      </div>

      {binding && (
        <button
          type="button"
          onClick={handleRevoke}
          disabled={isPending}
          className="text-xs font-medium text-destructive hover:text-destructive/80 disabled:opacity-50"
        >
          Revoke this card
        </button>
      )}

      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
