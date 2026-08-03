'use client'

import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'

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
  return (
    <div className="h-[260px] w-full text-xs" role="img" aria-label="Daily app events and errors for the last 14 days">
      <ResponsiveContainer initialDimension={{ width: 320, height: 200 }}>
        <LineChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
          <CartesianGrid vertical={false} stroke="var(--color-border)" strokeDasharray="3 3" />
          <XAxis dataKey="day" tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }} />
          <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={36} tick={{ fontSize: 11, fill: 'var(--color-muted-foreground)' }} />
          <Tooltip contentStyle={{ borderRadius: 8, fontSize: 12 }} />
          <Line type="monotone" dataKey="events" name="Events" stroke="var(--color-chart-1)" strokeWidth={2.5} dot={false} />
          <Line type="monotone" dataKey="errors" name="Errors" stroke="var(--color-chart-2)" strokeWidth={2.5} dot={false} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
