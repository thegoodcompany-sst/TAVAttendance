import { afterEach, describe, expect, it, vi } from 'vitest'
import { createClient } from '@/lib/supabase/server'
import { getHealthMetrics } from './health'

vi.mock('@/lib/supabase/server', () => ({ createClient: vi.fn() }))

afterEach(() => {
  vi.useRealTimers()
  vi.clearAllMocks()
})

describe('health chart fetch window', () => {
  it.each([
    // Sunday UTC is already Monday in Singapore.
    ['Monday', '2026-10-25T17:00:00Z', '2026-10-13', 1],
    ['Sunday', '2026-10-31T17:00:00Z', '2026-10-19', 7],
  ])('fetches all 14 days on %s while comparing calendar weeks', async (_day, now, start, currentDays) => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(now))
    // Include an extra day on either side to exercise both query bounds.
    const rows = Array.from({ length: 16 }, (_, index) => ({
      event_date: new Date(Date.parse(`${start}T00:00:00Z`) + (index - 1) * 86_400_000).toISOString().slice(0, 10),
      event_type: 'error', name: 'synthetic_error', event_count: 2, duration_ms_p95: null,
    }))
    let lower = ''
    let upper = ''
    const dailyQuery = {
      select: vi.fn().mockReturnThis(),
      gte: vi.fn((_column: string, value: string) => { lower = value; return dailyQuery }),
      lte: vi.fn((_column: string, value: string) => {
        upper = value
        return Promise.resolve({ data: rows.filter(row => row.event_date >= lower && row.event_date <= upper), error: null })
      }),
    }
    const syncQuery = {
      select: vi.fn().mockReturnThis(), in: vi.fn().mockReturnThis(),
      gte: vi.fn().mockResolvedValue({ data: [], error: null }),
    }
    vi.mocked(createClient).mockResolvedValue({
      from: (table: string) => {
        if (table === 'app_events_daily') return dailyQuery
        if (table === 'app_events') return syncQuery
        throw new Error(`Unexpected table: ${table}`)
      },
    } as unknown as Awaited<ReturnType<typeof createClient>>)

    const metrics = await getHealthMetrics()

    expect(metrics.daily).toEqual(rows.slice(1, 15).map(row => ({
      date: row.event_date, events: 2, errors: 2,
    })))
    expect(metrics.eventCount.current).toBe(currentDays * 2)
    expect(metrics.eventCount.previous).toBe(14)
    expect(metrics.errorRate).toEqual({ current: 100, previous: 100, delta: 0 })
    expect(syncQuery.gte).toHaveBeenCalledWith('occurred_at', '2026-10-19T00:00:00+08:00')
  })
})
