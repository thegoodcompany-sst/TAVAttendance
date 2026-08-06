import { describe, expect, it } from 'vitest'
import { summarizeByClass, yearWindowStart, type YearHistoryRecord } from './student-year-summary'

describe('yearWindowStart', () => {
  it('returns the Singapore calendar date one year earlier', () => {
    // Fixed UTC instant that is still 2026-08-07 in Singapore (UTC+8).
    const now = new Date('2026-08-07T01:00:00+08:00')
    expect(yearWindowStart(now)).toBe('2025-08-07')
  })
})

describe('summarizeByClass', () => {
  const records: YearHistoryRecord[] = [
    {
      id: '1', status: 'present', absenceInformed: null, markedAt: 't',
      sessionDate: '2026-01-01', classId: 'c1', className: 'P4 Math',
    },
    {
      id: '2', status: 'late', absenceInformed: null, markedAt: 't',
      sessionDate: '2026-01-02', classId: 'c1', className: 'P4 Math',
    },
    {
      id: '3', status: 'absent', absenceInformed: true, markedAt: 't',
      sessionDate: '2026-01-03', classId: 'c1', className: 'P4 Math',
    },
    {
      id: '4', status: 'present', absenceInformed: null, markedAt: 't',
      sessionDate: '2026-01-04', classId: 'c2', className: 'P4 English',
    },
  ]

  it('groups by class name ascending and computes attendance %', () => {
    const summaries = summarizeByClass(records)
    expect(summaries.map(s => s.className)).toEqual(['P4 English', 'P4 Math'])
    expect(summaries[1]).toMatchObject({
      totalSessions: 3,
      presentCount: 1,
      lateCount: 1,
      absentCount: 1,
      attendancePct: 66.7,
    })
    expect(summaries[0].attendancePct).toBe(100)
  })
})
