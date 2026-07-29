/* eslint-disable @typescript-eslint/no-explicit-any */
import { createClient } from '@/lib/supabase/server'
import { todayInTz, dateOffsetInTz, weekStartOf } from '@/lib/date'

export type HealthMetric = {
  current: number
  previous: number
  delta: number
}

export type HealthMetrics = {
  eventCount: HealthMetric
  errorRate: HealthMetric
  crashes: HealthMetric
  syncAttempts: HealthMetric
  syncFailureRate: HealthMetric
  latencies: Array<{ name: string } & HealthMetric>
  syncTotals: { synced: number; skipped: number; blockedEndedSession: number; pendingBefore: number }
  daily: Array<{ date: string; events: number; errors: number }>
}

function percentDelta(current: number, previous: number): number {
  if (previous === 0) return current === 0 ? 0 : 100
  return Math.round(((current - previous) / previous) * 1000) / 10
}

export async function getHealthMetrics(): Promise<HealthMetrics> {
  const supabase = await createClient()
  const today = todayInTz()
  const currentStart = weekStartOf(today)
  const previousStart = weekStartOf(dateOffsetInTz(-7))
  const previousEnd = new Date(Date.parse(`${currentStart}T00:00:00Z`) - 86_400_000).toISOString().slice(0, 10)

  const [{ data: dailyRows, error: dailyError }, { data: syncRows, error: syncError }] = await Promise.all([
    supabase
      .from('app_events_daily')
      .select('event_date, event_type, name, event_count, duration_ms_p95')
      .gte('event_date', previousStart)
      .lte('event_date', today),
    supabase
      .from('app_events')
      .select('occurred_at, name, properties')
      .in('name', ['sync_result', 'sync_failure'])
      .gte('occurred_at', `${previousStart}T00:00:00+08:00`),
  ])

  if (dailyError) throw new Error(`getHealthMetrics daily: ${dailyError.message}`)
  if (syncError) throw new Error(`getHealthMetrics sync: ${syncError.message}`)

  const rows = (dailyRows ?? []) as any[]
  const periodRows = (start: string, end?: string) => rows.filter(row =>
    row.event_date >= start && (!end || row.event_date <= end)
  )
  const count = (items: any[], predicate?: (row: any) => boolean) => items.reduce(
    (sum, row) => sum + (!predicate || predicate(row) ? Number(row.event_count) : 0),
    0,
  )
  const metric = (current: number, previous: number): HealthMetric => ({
    current,
    previous,
    delta: percentDelta(current, previous),
  })

  const currentRows = periodRows(currentStart)
  const previousRows = periodRows(previousStart, previousEnd)
  const currentEvents = count(currentRows)
  const previousEvents = count(previousRows)
  const currentErrors = count(currentRows, row => row.event_type === 'error')
  const previousErrors = count(previousRows, row => row.event_type === 'error')
  const currentCrashes = count(currentRows, row => row.event_type === 'crash')
  const previousCrashes = count(previousRows, row => row.event_type === 'crash')

  const sync = (syncRows ?? []) as any[]
  const singaporeDate = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
  const syncInPeriod = (start: string, end?: string) => sync.filter(row => {
    const date = singaporeDate.format(new Date(row.occurred_at))
    return date >= start && (!end || date <= end)
  })
  const syncFailureRate = (items: any[]) => {
    const failures = items.filter(row => row.name === 'sync_failure').length
    const attempts = items.filter(row => row.name === 'sync_failure' || row.name === 'sync_result').length
    return attempts > 0 ? Math.round((failures / attempts) * 1000) / 10 : 0
  }

  const latencyNames = [...new Set(rows.filter(row => row.duration_ms_p95 != null).map(row => row.name as string))]
  const latencyFor = (items: any[], name: string) => Math.max(
    0,
    ...items.filter(row => row.name === name).map(row => Number(row.duration_ms_p95) || 0),
  )

  const daily = Array.from({ length: 14 }, (_, index) => {
    const date = dateOffsetInTz(index - 13)
    const dayRows = rows.filter(row => row.event_date === date)
    return {
      date,
      events: count(dayRows),
      errors: count(dayRows, row => row.event_type === 'error' || row.event_type === 'crash'),
    }
  })

  const currentSync = syncInPeriod(currentStart)
  const previousSync = syncInPeriod(previousStart, previousEnd)
  const syncAttempts = (items: any[]) => items.filter(row => row.name === 'sync_failure' || row.name === 'sync_result').length
  const numberProperty = (row: any, key: string) => Number(row.properties?.[key]) || 0

  return {
    eventCount: metric(currentEvents, previousEvents),
    errorRate: metric(
      currentEvents > 0 ? Math.round((currentErrors / currentEvents) * 1000) / 10 : 0,
      previousEvents > 0 ? Math.round((previousErrors / previousEvents) * 1000) / 10 : 0,
    ),
    crashes: metric(currentCrashes, previousCrashes),
    syncAttempts: metric(syncAttempts(currentSync), syncAttempts(previousSync)),
    syncFailureRate: metric(syncFailureRate(currentSync), syncFailureRate(previousSync)),
    latencies: latencyNames.map(name => {
      const current = latencyFor(currentRows, name)
      const previous = latencyFor(previousRows, name)
      return { name, ...metric(current, previous) }
    }).sort((a, b) => b.current - a.current),
    syncTotals: currentSync.reduce((totals, row) => ({
      synced: totals.synced + numberProperty(row, 'synced'),
      skipped: totals.skipped + numberProperty(row, 'skipped'),
      blockedEndedSession: totals.blockedEndedSession + numberProperty(row, 'blocked_ended_session'),
      pendingBefore: totals.pendingBefore + numberProperty(row, 'pending_before'),
    }), { synced: 0, skipped: 0, blockedEndedSession: 0, pendingBefore: 0 }),
    daily,
  }
}
