'use client'

import { useState } from 'react'
import { LineChart, Line, XAxis, YAxis, CartesianGrid } from 'recharts'
import { ArrowDown, ArrowUp } from 'lucide-react'
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from '@/components/ui/chart'
import { cn } from '@/lib/utils'

export type ClassStat = {
  classId: string
  className: string
  attendancePct: number
  totalSessions: number
  students: number
}

export type StudentStat = {
  studentId: string
  studentName: string
  classCount: number
  totalSessions: number
  attendancePct: number
}

function riskBand(pct: number): { label: string; className: string } {
  if (pct >= 95) {
    return {
      label: 'Excellent',
      className: 'bg-emerald-50 text-emerald-700 border-emerald-200',
    }
  }
  if (pct >= 85) {
    return {
      label: 'Good',
      className: 'bg-emerald-50 text-emerald-700 border-emerald-200',
    }
  }
  if (pct >= 75) {
    return {
      label: 'Watch',
      className: 'bg-amber-50 text-amber-700 border-amber-200',
    }
  }
  return {
    label: 'At risk',
    className: 'bg-rose-50 text-rose-700 border-rose-200',
  }
}

/** Draft-style progress rows (replaces vertical recharts bar for visual parity). */
export function ClassAttendanceChart({ classes }: { classes: ClassStat[] }) {
  return (
    <div className="space-y-4">
      {classes.map(c => (
        <div key={c.classId}>
          <div className="mb-1.5 flex items-center justify-between text-sm">
            <span className="font-bold text-foreground">{c.className}</span>
            <span className="font-mono text-sm font-bold tabular-nums text-brand-ink">
              {c.attendancePct}%
            </span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-brand/10">
            <div
              className="h-full rounded-full bg-brand transition-[width]"
              style={{ width: `${Math.min(100, c.attendancePct)}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  )
}

export type WeeklyTrendPoint = {
  weekStart: string
  attendancePct: number
  totalRecords: number
}

function weekLabel(weekStart: string): string {
  return new Date(`${weekStart}T00:00:00Z`).toLocaleDateString('en-SG', {
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  })
}

export function WeeklyTrendChart({ points }: { points: WeeklyTrendPoint[] }) {
  const config = { attendancePct: { label: 'Attendance %' } }
  const data = points.map(p => ({ ...p, week: weekLabel(p.weekStart) }))
  return (
    <ChartContainer config={config} className="h-[220px] w-full">
      <LineChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
        <CartesianGrid vertical={false} stroke="var(--color-border)" strokeDasharray="3 3" />
        <XAxis
          dataKey="week"
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }}
        />
        <YAxis
          domain={[0, 100]}
          tickLine={false}
          axisLine={false}
          width={36}
          tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }}
          unit="%"
        />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Line
          type="monotone"
          dataKey="attendancePct"
          stroke="var(--color-chart-1)"
          strokeWidth={2.5}
          dot={{ r: 3, fill: 'var(--color-chart-1)' }}
          activeDot={{ r: 5, stroke: 'var(--color-accent-marigold)', strokeWidth: 2 }}
        />
      </LineChart>
    </ChartContainer>
  )
}

type SortKey = 'studentName' | 'attendancePct' | 'totalSessions' | 'classCount'

export function StudentAttendanceTable({ students }: { students: StudentStat[] }) {
  const [sortKey, setSortKey] = useState<SortKey>('attendancePct')
  const [asc, setAsc] = useState(false)

  const sorted = [...students].sort((a, b) => {
    let d: number
    if (sortKey === 'studentName') d = a.studentName.localeCompare(b.studentName)
    else d = (a[sortKey] as number) - (b[sortKey] as number)
    return asc ? d : -d
  })

  function toggle(key: SortKey) {
    if (key === sortKey) setAsc(v => !v)
    else {
      setSortKey(key)
      setAsc(key === 'studentName')
    }
  }

  const header = (label: string, k: SortKey, align?: 'right') => (
    <th
      className={cn(
        'bg-muted/70 px-5 py-3 text-[0.7rem] font-bold uppercase tracking-wide text-muted-foreground',
        align === 'right' ? 'text-right' : 'text-left',
      )}
    >
      <button
        onClick={() => toggle(k)}
        className={cn(
          'inline-flex items-center gap-1 hover:text-foreground transition-colors',
          align === 'right' && 'flex-row-reverse',
        )}
      >
        {label}
        {sortKey === k && (asc
          ? <ArrowUp size={13} className="text-brand-ink" />
          : <ArrowDown size={13} className="text-brand-ink" />)}
      </button>
    </th>
  )

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr>
            {header('Student', 'studentName')}
            {header('Classes', 'classCount')}
            {header('Sessions', 'totalSessions', 'right')}
            {header('Rate', 'attendancePct', 'right')}
            <th className="bg-muted/70 px-5 py-3 text-left text-[0.7rem] font-bold uppercase tracking-wide text-muted-foreground">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {sorted.map(s => {
            const band = riskBand(s.attendancePct)
            const atRisk = s.attendancePct < 75
            return (
              <tr
                key={s.studentId}
                className={cn(
                  'border-t border-border hover:bg-muted/40 transition-colors',
                  atRisk && 'bg-rose-50/40',
                )}
              >
                <td className="px-5 py-3 font-bold text-foreground">{s.studentName}</td>
                <td className="px-5 py-3 text-muted-foreground">{s.classCount}</td>
                <td className="px-5 py-3 text-right font-mono tabular-nums text-muted-foreground">
                  {s.totalSessions}
                </td>
                <td
                  className={cn(
                    'px-5 py-3 text-right font-mono text-sm font-bold tabular-nums',
                    atRisk ? 'text-rose-600' : s.attendancePct < 85 ? 'text-amber-600' : 'text-brand-ink',
                  )}
                >
                  {s.attendancePct}%
                </td>
                <td className="px-5 py-3">
                  <span
                    className={cn(
                      'inline-flex items-center rounded-full border px-2.5 py-0.5 text-[0.7rem] font-bold',
                      band.className,
                    )}
                  >
                    {band.label}
                  </span>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
