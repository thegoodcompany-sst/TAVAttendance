'use client'

import {
  LineChart,
  Line,
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
    <ChartContainer config={chartConfig} className="h-[220px] w-full">
      <LineChart data={formatted} margin={{ top: 8, right: 4, left: -24, bottom: 0 }}>
        <CartesianGrid
          vertical={false}
          stroke="var(--color-brand)"
          strokeOpacity={0.12}
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
        <Line
          type="monotone"
          dataKey="present"
          stroke="var(--color-chart-1)"
          strokeWidth={2.5}
          dot={false}
          activeDot={{ r: 4, strokeWidth: 0, fill: 'var(--color-chart-1)' }}
        />
        <Line
          type="monotone"
          dataKey="late"
          stroke="var(--color-chart-2)"
          strokeWidth={2.5}
          dot={false}
          activeDot={{ r: 4, strokeWidth: 0, fill: 'var(--color-chart-2)' }}
        />
      </LineChart>
    </ChartContainer>
  )
}
