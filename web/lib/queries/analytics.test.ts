import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createClient } from '@/lib/supabase/server'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { dateOffsetInTz, todayInTz } from '@/lib/date'
import { getAttendanceAnalytics, getMonthlyAttendanceDrops, getWeeklyAttendanceTrend } from './analytics'

vi.mock('@/lib/supabase/server', () => ({ createClient: vi.fn() }))
vi.mock('@/lib/feature-flags', () => ({ isFeatureEnabled: vi.fn(async () => false) }))
vi.mock('@/lib/date', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/date')>(),
  todayInTz: vi.fn(() => '2026-10-22'),
  dateOffsetInTz: vi.fn(() => '2026-08-03'),
}))

function record(id: number, date: string, status: string) {
  return {
    id: String(id).padStart(6, '0'), status, student_id: 'synthetic-student',
    student: { full_name: 'Test Student', is_active: true },
    session: { session_date: date, class: { is_study_space: false, is_active: true } },
  }
}

// Enforce the API cap even when the caller forgets to request a range.
function mockClient(rows: ReturnType<typeof record>[], cap = 1000, failFrom?: number, mutate?: () => void) {
  const queries: ReturnType<typeof makeQuery>[] = []
  function makeQuery() {
    let after = ''
    let offset = 0
    let end = cap - 1
    const query = {
      select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(),
      gte: vi.fn().mockReturnThis(), lte: vi.fn().mockReturnThis(),
      order: vi.fn().mockReturnThis(),
      gt: vi.fn((_key: string, value: string) => { after = value; return query }),
      limit: vi.fn((count: number) => { end = count - 1; return query }),
      range: vi.fn((from: number, to: number) => { offset = from; end = to; return query }),
      then: (resolve: (value: unknown) => unknown) => Promise.resolve(
        failFrom !== undefined && queries.length > 1
          ? { data: null, error: { message: 'page unavailable' } }
          : { data: rows.filter(row => row.id > after).slice(offset, Math.min(end + 1, offset + cap)), error: null },
      ).then(resolve),
    }
    return query
  }
  const from = vi.fn(() => {
    if (queries.length === 1) mutate?.()
    const query = makeQuery()
    queries.push(query)
    return query
  })
  vi.mocked(createClient).mockResolvedValue({ from } as unknown as Awaited<ReturnType<typeof createClient>>)
  return { queries, from }
}

function expectFilters(queries: ReturnType<typeof mockClient>['queries'], start: string) {
  for (const query of queries) {
    expect(query.order).toHaveBeenCalledWith('id', { ascending: true })
    expect(query.eq).toHaveBeenCalledWith('session.class.is_study_space', false)
    expect(query.eq).toHaveBeenCalledWith('session.class.is_active', true)
    expect(query.eq).toHaveBeenCalledWith('student.is_active', true)
    expect(query.gte).toHaveBeenCalledWith('session.session_date', start)
    expect(query.lte).toHaveBeenCalledWith('session.session_date', '2026-10-22')
  }
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.mocked(todayInTz).mockReturnValue('2026-10-22')
  vi.mocked(dateOffsetInTz).mockReturnValue('2026-08-03')
  vi.mocked(isFeatureEnabled).mockResolvedValue(false)
})

describe('analytics pagination', () => {
  it('includes both months beyond the 1,000-row cap', async () => {
    const rows = [
      ...Array.from({ length: 1000 }, (_, i) => record(i, '2026-09-07', 'present')),
      ...Array.from({ length: 500 }, (_, i) => record(1000 + i, '2026-10-05', 'absent')),
      ...Array.from({ length: 500 }, (_, i) => record(1500 + i, '2026-10-08', 'late')),
    ]
    const { queries, from } = mockClient(rows)
    expect(await getMonthlyAttendanceDrops()).toEqual([{
      studentId: 'synthetic-student', studentName: 'Test Student',
      thisMonthPct: 50, lastMonthPct: 100, delta: -50,
      thisMonthSessions: 1000, lastMonthSessions: 1000,
    }])
    expect(from).toHaveBeenCalledTimes(3)
    expect(queries.map(q => q.gt.mock.calls[0])).toEqual([undefined, ['id', '000999'], ['id', '001999']])
    expectFilters(queries, '2026-09-01')
  })

  it.each([1000, 400])('calculates weekly percentages from all records with API cap %i', async (cap) => {
    const rows = [
      ...Array.from({ length: 1000 }, (_, i) => record(i, '2026-10-05', 'present')),
      ...Array.from({ length: 500 }, (_, i) => record(1000 + i, '2026-10-08', 'absent')),
    ]
    const { queries } = mockClient(rows, cap)
    expect(await getWeeklyAttendanceTrend()).toEqual([
      { weekStart: '2026-10-05', attendancePct: 66.7, totalRecords: 1500 },
    ])
    expectFilters(queries, '2026-08-03')
  })

  it.each([['monthly', getMonthlyAttendanceDrops], ['weekly', getWeeklyAttendanceTrend]] as const)('rejects incomplete results after a later page fails (%s)', async (_name, fetch) => {
    mockClient(Array.from({ length: 1000 }, (_, i) => record(i, '2026-10-05', 'present')), 1000, 1000)
    await expect(fetch()).rejects.toThrow('page unavailable')
  })

  it.each([['monthly', getMonthlyAttendanceDrops], ['weekly', getWeeklyAttendanceTrend]] as const)('returns an empty report for an empty window (%s)', async (_name, fetch) => {
    const { from } = mockClient([])
    expect(await fetch()).toEqual([])
    expect(from).toHaveBeenCalledTimes(1)
  })
})

it.each(['delete', 'insert'])('avoids shifted pages after concurrent %s', async change => {
  const rows = [record(1, '2026-09-07', 'present'), record(2, '2026-09-07', 'absent'), record(3, '2026-10-05', 'present')]
  mockClient(rows, 2, undefined, () => {
    if (change === 'delete') rows.shift()
    else rows.unshift(record(0, '2026-09-07', 'absent'))
  })
  expect(await getMonthlyAttendanceDrops()).toEqual([{
    studentId: 'synthetic-student', studentName: 'Test Student',
    thisMonthPct: 100, lastMonthPct: 50, delta: 50, thisMonthSessions: 1, lastMonthSessions: 2,
  }])
  const weeklyRows = [record(1, '2026-10-05', 'present'), record(2, '2026-10-05', 'absent'), record(3, '2026-10-05', 'present')]
  mockClient(weeklyRows, 2, undefined, () => {
    if (change === 'delete') weeklyRows.shift()
    else weeklyRows.unshift(record(0, '2026-10-05', 'absent'))
  })
  expect(await getWeeklyAttendanceTrend()).toEqual([{ weekStart: '2026-10-05', attendancePct: 66.7, totalRecords: 3 }])
})


describe('shared analytics scan', () => {
  it.each([false, true])('fetches the union once and preserves monthly boundaries and test mode (%s)', async testMode => {
    vi.mocked(isFeatureEnabled).mockResolvedValue(testMode)
    const { from, queries } = mockClient([
      record(1, '2026-08-03', 'absent'),
      record(2, '2026-09-07', 'present'),
      record(3, '2026-10-05', 'late'),
      record(4, '2026-10-08', 'absent'),
      record(5, '2026-10-10', 'present'),
    ], 2)
    const result = await getAttendanceAnalytics()
    expect(result.drops).toEqual([{
      studentId: 'synthetic-student', studentName: 'Test Student',
      thisMonthPct: testMode ? 66.7 : 50, lastMonthPct: 100,
      delta: testMode ? -33.3 : -50,
      thisMonthSessions: testMode ? 3 : 2, lastMonthSessions: 1,
    }])
    expect(result.weeklyTrend).toEqual([
      { weekStart: '2026-08-03', attendancePct: 0, totalRecords: 1 },
      { weekStart: '2026-09-07', attendancePct: 100, totalRecords: 1 },
      { weekStart: '2026-10-05', attendancePct: testMode ? 66.7 : 50, totalRecords: testMode ? 3 : 2 },
    ])
    expect(createClient).toHaveBeenCalledTimes(1)
    expect(isFeatureEnabled).toHaveBeenCalledTimes(1)
    expect(from).toHaveBeenCalledTimes(4) // three capped pages and the empty terminator
    expectFilters(queries, '2026-08-03')
  })

  it('fetches the monthly window when it starts earlier, including across a year boundary', async () => {
    vi.mocked(todayInTz).mockReturnValue('2027-01-07')
    vi.mocked(dateOffsetInTz).mockReturnValue('2027-01-04')
    const { queries } = mockClient([
      record(1, '2026-12-07', 'present'), record(2, '2027-01-04', 'absent'),
    ])
    const result = await getAttendanceAnalytics(1)
    expect(result.drops[0]).toMatchObject({ lastMonthPct: 100, thisMonthPct: 0, delta: -100 })
    expect(result.weeklyTrend).toEqual([{ weekStart: '2027-01-04', attendancePct: 0, totalRecords: 1 }])
    for (const query of queries) {
      expect(query.gte).toHaveBeenCalledWith('session.session_date', '2026-12-01')
      expect(query.lte).toHaveBeenCalledWith('session.session_date', '2027-01-07')
    }
  })

  it('does not reuse attendance from an earlier request/client', async () => {
    mockClient([record(1, '2026-10-05', 'present')])
    expect((await getAttendanceAnalytics()).weeklyTrend).toHaveLength(1)
    mockClient([])
    expect(await getAttendanceAnalytics()).toEqual({ drops: [], weeklyTrend: [] })
    expect(createClient).toHaveBeenCalledTimes(2)
  })

  it('rejects both aggregates if a later shared page fails', async () => {
    mockClient([record(1, '2026-09-07', 'present'), record(2, '2026-10-05', 'absent')], 1, 1)
    await expect(getAttendanceAnalytics()).rejects.toThrow('page unavailable')
  })
})
