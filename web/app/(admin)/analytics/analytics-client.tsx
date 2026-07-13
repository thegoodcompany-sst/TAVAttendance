'use client'

import { useState } from 'react'
import { BarChart, Bar, LineChart, Line, XAxis, YAxis, CartesianGrid, Cell } from 'recharts'
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

function pctColor(pct: number): string {
  if (pct >= 90) return 'var(--color-chart-1)'
  if (pct >= 75) return 'var(--color-accent-marigold)'
  return 'var(--color-chart-2)'
}

export function ClassAttendanceChart({ classes }: { classes: ClassStat[] }) {
  const config = { attendancePct: { label: 'Attendance %' } }
  return (
    <ChartContainer config={config} className="h-[280px] w-full">
      <BarChart
        data={classes}
        layout="vertical"
        margin={{ top: 4, right: 12, left: 8, bottom: 0 }}
      >
        <CartesianGrid horizontal={false} stroke="var(--color-border)" strokeDasharray="3 3" />
        <XAxis
          type="number"
          domain={[0, 100]}
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }}
          unit="%"
        />
        <YAxis
          type="category"
          dataKey="className"
          tickLine={false}
          axisLine={false}
          width={110}
          tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }}
        />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Bar dataKey="attendancePct" radius={[0, 6, 6, 0]} maxBarSize={26}>
          {classes.map(c => (
            <Cell key={c.classId} fill={pctColor(c.attendancePct)} />
          ))}
        </Bar>
      </BarChart>
    </ChartContainer>
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
          activeDot={{ r: 5 }}
        />
      </LineChart>
    </ChartContainer>
  )
}

type SortKey = 'studentName' | 'attendancePct' | 'totalSessions'

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
    <th className={cn('px-4 py-3 font-medium', align === 'right' ? 'text-right' : 'text-left')}>
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
        <thead className="text-xs uppercase tracking-wide text-muted-foreground border-b border-border">
          <tr>
            {header('Student', 'studentName')}
            {header('Sessions', 'totalSessions', 'right')}
            {header('Attendance', 'attendancePct', 'right')}
          </tr>
        </thead>
        <tbody>
          {sorted.map(s => (
            <tr key={s.studentId} className="border-b border-border/60 last:border-0 hover:bg-muted/40 transition-colors">
              <td className="px-4 py-3">
                <p className="font-medium">{s.studentName}</p>
                <p className="text-xs text-muted-foreground">
                  {s.classCount} class{s.classCount !== 1 ? 'es' : ''}
                </p>
              </td>
              <td className="px-4 py-3 text-right tabular-nums text-muted-foreground">{s.totalSessions}</td>
              <td className="px-4 py-3">
                <div className="flex items-center justify-end gap-2.5">
                  <div className="hidden sm:block w-24 h-1.5 rounded-full bg-muted overflow-hidden">
                    <div
                      className="h-full rounded-full"
                      style={{ width: `${s.attendancePct}%`, backgroundColor: pctColor(s.attendancePct) }}
                    />
                  </div>
                  <span className="font-medium tabular-nums w-11 text-right">{s.attendancePct}%</span>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
