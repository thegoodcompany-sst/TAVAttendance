'use client'

import { Line, LineChart, XAxis, YAxis, CartesianGrid } from 'recharts'
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart'

export function HealthEventsChart({
  points,
}: {
  points: Array<{ date: string; events: number; errors: number }>
}) {
  const data = points.map(point => ({
    ...point,
    day: new Date(`${point.date}T00:00:00Z`).toLocaleDateString('en-SG', {
      day: 'numeric',
      month: 'short',
      timeZone: 'UTC',
    }),
  }))
  const config = {
    events: { label: 'Events', color: 'var(--color-chart-1)' },
    errors: { label: 'Errors', color: 'var(--color-chart-2)' },
  }

  return (
    <ChartContainer config={config} className="h-[260px] w-full" role="img" aria-label="Daily app events and errors for the last 14 days">
      <LineChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
        <CartesianGrid vertical={false} stroke="var(--color-border)" strokeDasharray="3 3" />
        <XAxis dataKey="day" tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }} />
        <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={36} tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }} />
        <ChartTooltip content={<ChartTooltipContent />} />
        <Line type="monotone" dataKey="events" stroke="var(--color-chart-1)" strokeWidth={2.5} dot={false} />
        <Line type="monotone" dataKey="errors" stroke="var(--color-chart-2)" strokeWidth={2.5} dot={false} />
      </LineChart>
    </ChartContainer>
  )
}
