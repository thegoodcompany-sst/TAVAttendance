import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createClient } from '@/lib/supabase/server'
import { getMonthlyAttendanceDrops, getWeeklyAttendanceTrend } from './analytics'

vi.mock('@/lib/supabase/server', () => ({ createClient: vi.fn() }))
vi.mock('@/lib/feature-flags', () => ({ isFeatureEnabled: vi.fn(async () => false) }))
vi.mock('@/lib/date', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/date')>(),
  todayInTz: () => '2026-10-22',
  dateOffsetInTz: () => '2026-08-03',
}))

function record(id: number, date: string, status: string) {
  return {
    id: String(id).padStart(6, '0'), status, student_id: 'synthetic-student',
    student: { full_name: 'Test Student', is_active: true },
    session: { session_date: date, class: { is_study_space: false, is_active: true } },
  }
}

// Enforce the API cap even when the caller forgets to request a range.
function mockClient(rows: ReturnType<typeof record>[], cap = 1000, failFrom?: number) {
  const queries: ReturnType<typeof makeQuery>[] = []
  function makeQuery() {
    let offset = 0
    let end = cap - 1
    const query = {
      select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(),
      gte: vi.fn().mockReturnThis(), lte: vi.fn().mockReturnThis(),
      order: vi.fn().mockReturnThis(),
      range: vi.fn((from: number, to: number) => { offset = from; end = to; return query }),
      then: (resolve: (value: unknown) => unknown) => Promise.resolve(
        failFrom !== undefined && offset >= failFrom
          ? { data: null, error: { message: 'page unavailable' } }
          : { data: rows.slice(offset, Math.min(end + 1, offset + cap)), error: null },
      ).then(resolve),
    }
    return query
  }
  const from = vi.fn(() => {
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

beforeEach(() => vi.clearAllMocks())

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
    expect(queries.map(q => q.range.mock.calls[0])).toEqual([[0, 999], [1000, 1999], [2000, 2999]])
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
