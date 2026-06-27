'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Download, ShieldOff, Trash2, EraserIcon, Loader2 } from 'lucide-react'
import {
  anonymiseStudent,
  eraseStudent,
  exportStudentData,
  withdrawConsent,
} from '@/app/actions/students'
import type { ConsentRecord } from '@/lib/queries'

function statusColor(status: string) {
  return status === 'granted'
    ? 'text-emerald-700 bg-emerald-50'
    : 'text-rose-700 bg-rose-50'
}

export function PdpaPanel({
  studentId,
  studentName,
  consent,
}: {
  studentId: string
  studentName: string
  consent: ConsentRecord[]
}) {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [confirm, setConfirm] = useState<null | 'anonymise' | 'erase'>(null)
  const [isPending, startTransition] = useTransition()

  const handleExport = () => {
    setError(null)
    startTransition(async () => {
      const { error, json } = await exportStudentData(studentId)
      if (error || !json) {
        setError(error ?? 'Export failed.')
        return
      }
      const blob = new Blob([json], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      const date = new Date().toISOString().slice(0, 10)
      a.href = url
      a.download = `pdpa-export-${studentId}-${date}.json`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
    })
  }

  const handleWithdraw = (consentType: string) => {
    setError(null)
    startTransition(async () => {
      const { error } = await withdrawConsent(studentId, consentType)
      if (error) setError(error)
      else router.refresh()
    })
  }

  const handleAnonymise = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await anonymiseStudent(studentId)
      if (error) {
        setError(error)
        setConfirm(null)
      } else {
        router.push('/students')
        router.refresh()
      }
    })
  }

  const handleErase = () => {
    setError(null)
    startTransition(async () => {
      const { error } = await eraseStudent(studentId)
      if (error) {
        setError(error)
        setConfirm(null)
      } else {
        router.push('/students')
        router.refresh()
      }
    })
  }

  return (
    <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)] space-y-5">
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
        Privacy &amp; consent
      </p>

      {/* Consent ledger */}
      <div className="space-y-2">
        {consent.length === 0 ? (
          <p className="text-sm text-muted-foreground">No consent records.</p>
        ) : (
          consent.map(c => (
            <div key={c.consentType} className="flex items-center justify-between gap-3 text-sm">
              <div className="min-w-0">
                <span className="font-medium">{c.consentType.replace(/_/g, ' ')}</span>
                <span className="text-xs text-muted-foreground ml-2">
                  {c.method.replace(/_/g, ' ')}
                  {c.noticeVersion ? ` · notice v${c.noticeVersion}` : ''}
                </span>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${statusColor(c.status)}`}>
                  {c.status}
                </span>
                {c.status === 'granted' && (
                  <button
                    onClick={() => handleWithdraw(c.consentType)}
                    disabled={isPending}
                    className="text-xs text-muted-foreground hover:text-destructive transition-colors disabled:opacity-50"
                  >
                    Withdraw
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Subject-access export */}
      <button
        onClick={handleExport}
        disabled={isPending}
        className="inline-flex items-center gap-1.5 text-sm font-medium text-brand-ink hover:text-brand transition-colors disabled:opacity-50"
      >
        {isPending ? <Loader2 size={14} className="animate-spin" /> : <Download size={14} />}
        Export this student&apos;s data (JSON)
      </button>

      {/* Erasure / anonymisation */}
      <div className="pt-2 border-t border-border space-y-2">
        {confirm === null && (
          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={() => setConfirm('anonymise')}
              disabled={isPending}
              className="inline-flex items-center gap-1.5 text-xs font-medium text-amber-700 bg-amber-50 hover:bg-amber-100 px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50"
            >
              <ShieldOff size={13} /> Anonymise
            </button>
            <button
              onClick={() => setConfirm('erase')}
              disabled={isPending}
              className="inline-flex items-center gap-1.5 text-xs font-medium text-destructive bg-destructive/8 hover:bg-destructive/15 px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50"
            >
              <Trash2 size={13} /> Erase
            </button>
          </div>
        )}

        {confirm === 'anonymise' && (
          <div className="text-sm space-y-2">
            <p className="text-muted-foreground">
              Redact <span className="font-medium text-foreground">{studentName}</span>&apos;s
              personal data, keeping anonymous attendance counts? This cannot be undone.
            </p>
            <div className="flex items-center gap-2">
              <button onClick={handleAnonymise} disabled={isPending} className="inline-flex items-center gap-1 text-xs font-medium text-amber-700 hover:text-amber-800 disabled:opacity-50">
                {isPending ? <Loader2 size={12} className="animate-spin" /> : <ShieldOff size={12} />}
                Yes, anonymise
              </button>
              <span className="text-muted-foreground text-xs">·</span>
              <button onClick={() => setConfirm(null)} className="text-xs text-muted-foreground hover:text-foreground">Cancel</button>
            </div>
          </div>
        )}

        {confirm === 'erase' && (
          <div className="text-sm space-y-2">
            <p className="text-muted-foreground">
              Permanently erase <span className="font-medium text-foreground">{studentName}</span> and
              scrub audit snapshots? This is a hard delete and cannot be undone.
            </p>
            <div className="flex items-center gap-2">
              <button onClick={handleErase} disabled={isPending} className="inline-flex items-center gap-1 text-xs font-medium text-destructive hover:text-destructive/80 disabled:opacity-50">
                {isPending ? <Loader2 size={12} className="animate-spin" /> : <EraserIcon size={12} />}
                Yes, erase permanently
              </button>
              <span className="text-muted-foreground text-xs">·</span>
              <button onClick={() => setConfirm(null)} className="text-xs text-muted-foreground hover:text-foreground">Cancel</button>
            </div>
          </div>
        )}
      </div>

      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
