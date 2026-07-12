'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Award, Clock, Loader2, Check } from 'lucide-react'
import { giveAward, type AwardType } from '@/app/actions/awards'
import type { AwardCandidate, GivenAward } from '@/lib/queries'

type Props = {
  period: string
  periods: string[]
  byAttendance: AwardCandidate[]
  byPunctuality: AwardCandidate[]
  given: GivenAward[]
}

export function AwardsClient({ period, periods, byAttendance, byPunctuality, given }: Props) {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const hasAward = (studentId: string, type: AwardType) =>
    given.some(g => g.studentId === studentId && g.awardType === type)

  const handleGive = (studentId: string, type: AwardType) => {
    setError(null)
    startTransition(async () => {
      const { error } = await giveAward(studentId, type, period)
      if (error) setError(error)
      else router.refresh()
    })
  }

  const column = (
    title: string,
    Icon: typeof Award,
    type: AwardType,
    rows: AwardCandidate[],
    metric: (c: AwardCandidate) => string,
  ) => (
    <div className="flex-1 bg-white rounded-3xl p-6 shadow-card min-w-0">
      <div className="flex items-center gap-2 mb-4">
        <Icon size={18} className="text-brand-ink" />
        <h2 className="font-display text-lg font-semibold">{title}</h2>
      </div>
      {rows.length === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-8">No candidates yet.</p>
      ) : (
        <div className="space-y-1">
          {rows.map(c => {
            const done = hasAward(c.studentId, type)
            return (
              <div key={c.studentId} className="flex items-center gap-3 px-3 py-2 rounded-2xl hover:bg-muted/50 transition-colors">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{c.studentName}</p>
                  <p className="text-xs text-muted-foreground tabular-nums">{metric(c)}</p>
                </div>
                {done ? (
                  <span className="inline-flex items-center gap-1 text-xs font-medium text-emerald-600">
                    <Check size={13} /> Awarded
                  </span>
                ) : (
                  <button
                    onClick={() => handleGive(c.studentId, type)}
                    disabled={isPending}
                    className="text-xs font-medium text-brand-ink bg-brand-soft hover:bg-brand-soft/70 rounded-full px-3 py-1 transition-colors disabled:opacity-50"
                  >
                    Give
                  </button>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )

  return (
    <>
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <label className="text-sm text-muted-foreground flex items-center gap-2">
          Period
          <select
            value={period}
            onChange={e => router.push(`/awards?period=${e.target.value}`)}
            className="text-sm rounded-lg border border-border bg-background px-2.5 py-1.5 outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
          >
            {periods.map(p => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
        </label>
        {isPending && <Loader2 size={16} className="animate-spin text-muted-foreground" />}
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex flex-col lg:flex-row gap-6">
        {column('Perfect attendance', Award, 'perfect_attendance', byAttendance, c => `${c.attendancePct}% · ${c.totalSessions} sessions`)}
        {column('Punctuality', Clock, 'punctuality', byPunctuality, c => `${c.lateCount} late · ${c.totalSessions} sessions`)}
      </div>

      <div className="bg-white rounded-3xl p-6 shadow-card">
        <h2 className="font-display text-lg font-semibold mb-4">Awarded this period</h2>
        {given.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-6">No awards given for {period} yet.</p>
        ) : (
          <div className="space-y-1">
            {given.map(g => (
              <div key={g.id} className="flex items-center gap-3 px-3 py-2 rounded-2xl">
                <span className="flex-1 min-w-0 text-sm font-medium truncate">{g.studentName}</span>
                <span className="text-xs text-muted-foreground">{g.awardType.replace(/_/g, ' ')}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </>
  )
}
