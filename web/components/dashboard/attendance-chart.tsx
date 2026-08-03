'use client'

import type { DailyAttendancePoint } from '@/lib/queries/analytics'
import { cn } from '@/lib/utils'

/**
 * Paired present/late bars matching docs/drafts/web-dashboard-ui.html.
 * Heights are relative to the max present+late count in the window so empty
 * days still leave room for labels without looking broken.
 */
export function AttendanceChart({ data }: { data: DailyAttendancePoint[] }) {
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())

  const max = Math.max(
    1,
    ...data.map(d => Math.max(d.present + d.late, d.present, d.late)),
  )

  if (data.length === 0) {
    return (
      <div className="flex h-44 items-center justify-center rounded-[1.25rem] bg-white p-5 shadow-card">
        <p className="text-sm text-muted-foreground">No attendance in the last 14 days.</p>
      </div>
    )
  }

  return (
    <div className="rounded-[1.25rem] bg-white p-5 shadow-card">
      <div className="flex h-44 items-end justify-between gap-1.5 sm:gap-2">
        {data.map(d => {
          const presentPct = Math.max(0, Math.round((d.present / max) * 100))
          const latePct = Math.max(0, Math.round((d.late / max) * 100))
          const isToday = d.date === today
          const label = new Date(`${d.date}T12:00:00Z`).toLocaleDateString('en-SG', {
            month: 'short',
            day: 'numeric',
            timeZone: 'Asia/Singapore',
          })

          return (
            <div
              key={d.date}
              className="flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-2"
              title={`${label}: ${d.present} present, ${d.late} late`}
            >
              <div className="flex h-full w-full items-end justify-center gap-0.5">
                <div
                  className={cn(
                    'w-[40%] max-w-5 rounded-t-sm bg-brand transition-[height]',
                    isToday && 'shadow-[0_0_0_2px_rgba(17,109,255,0.35)]',
                  )}
                  style={{ height: `${presentPct}%`, minHeight: d.present > 0 ? 4 : 0 }}
                />
                <div
                  className="w-[40%] max-w-5 rounded-t-sm bg-accent-marigold transition-[height]"
                  style={{ height: `${latePct}%`, minHeight: d.late > 0 ? 4 : 0 }}
                />
              </div>
              <span
                className={cn(
                  'font-mono text-[0.6rem] tabular-nums text-muted-foreground',
                  isToday && 'font-bold text-brand',
                )}
              >
                {label}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
