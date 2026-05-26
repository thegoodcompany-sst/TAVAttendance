'use client'

import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
} from 'recharts'
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from '@/components/ui/chart'
import type { DailyAttendancePoint } from '@/lib/queries'

const chartConfig = {
  present: { label: 'Present', color: 'var(--color-chart-1)' },
  late: { label: 'Late', color: 'var(--color-chart-2)' },
}

export function AttendanceChart({ data }: { data: DailyAttendancePoint[] }) {
  const formatted = data.map(d => ({
    ...d,
    label: new Date(d.date + 'T12:00:00Z').toLocaleDateString('en-SG', {
      month: 'short',
      day: 'numeric',
      timeZone: 'Asia/Singapore',
    }),
  }))

  return (
    <ChartContainer config={chartConfig} className="h-[200px] w-full">
      <AreaChart data={formatted} margin={{ top: 4, right: 0, left: -24, bottom: 0 }}>
        <defs>
          <linearGradient id="grad-present" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--color-chart-1)" stopOpacity={0.2} />
            <stop offset="100%" stopColor="var(--color-chart-1)" stopOpacity={0} />
          </linearGradient>
          <linearGradient id="grad-late" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--color-chart-2)" stopOpacity={0.2} />
            <stop offset="100%" stopColor="var(--color-chart-2)" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid
          strokeDasharray="3 3"
          vertical={false}
          stroke="var(--color-border)"
        />
        <XAxis
          dataKey="label"
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }}
          interval="preserveStartEnd"
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }}
          allowDecimals={false}
          width={32}
        />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Area
          type="monotone"
          dataKey="present"
          stroke="var(--color-chart-1)"
          strokeWidth={2.5}
          fill="url(#grad-present)"
          dot={false}
          activeDot={{ r: 4, strokeWidth: 0, fill: 'var(--color-chart-1)' }}
        />
        <Area
          type="monotone"
          dataKey="late"
          stroke="var(--color-chart-2)"
          strokeWidth={2.5}
          fill="url(#grad-late)"
          dot={false}
          activeDot={{ r: 4, strokeWidth: 0, fill: 'var(--color-chart-2)' }}
        />
      </AreaChart>
    </ChartContainer>
  )
}
