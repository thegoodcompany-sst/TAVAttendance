import { describe, expect, it } from 'vitest'
import {
  attendancePct,
  countAttendanceStatuses,
  filterDatesByTuitionDay,
  monthlyDropsFromBuckets,
  weeklyAttendanceFromRecords,
} from './queries/analytics-helpers'
import { auditEntityLabel, parseAuditCursor } from './queries/activity-helpers'
import { weekStartOf } from './date'

describe('attendance status counting', () => {
  it('counts present, late, and excused', () => {
    expect(
      countAttendanceStatuses(['present', 'late', 'excused', 'absent', 'present', null]),
    ).toEqual({ present: 2, late: 1, excused: 1 })
  })
})

describe('tuition-day filtering', () => {
  // 2026-07-13 is Monday, 2026-07-14 Tuesday, 2026-07-16 Thursday.
  const dates = ['2026-07-13', '2026-07-14', '2026-07-16']

  it('keeps only Mon/Thu when test_mode is off', () => {
    expect(filterDatesByTuitionDay(dates, false)).toEqual(['2026-07-13', '2026-07-16'])
  })

  it('keeps every day when test_mode is on', () => {
    expect(filterDatesByTuitionDay(dates, true)).toEqual(dates)
  })
})

describe('monthly comparison', () => {
  it('requires records in both periods and sorts by largest drop', () => {
    const result = monthlyDropsFromBuckets([
      {
        studentId: 'a',
        studentName: 'A',
        thisMonth: { total: 4, attended: 2 },
        lastMonth: { total: 4, attended: 4 },
      },
      {
        studentId: 'b',
        studentName: 'B',
        thisMonth: { total: 2, attended: 2 },
        lastMonth: { total: 0, attended: 0 },
      },
      {
        studentId: 'c',
        studentName: 'C',
        thisMonth: { total: 4, attended: 3 },
        lastMonth: { total: 4, attended: 2 },
      },
    ])
    expect(result.map((r) => r.studentId)).toEqual(['a', 'c'])
    expect(result[0].delta).toBeLessThan(0)
  })
})

describe('weekly aggregation', () => {
  it('uses Monday week starts', () => {
    // Wed 2026-07-15 and Mon 2026-07-13 share week starting 2026-07-13.
    expect(weekStartOf('2026-07-15')).toBe('2026-07-13')
    const points = weeklyAttendanceFromRecords([
      { date: '2026-07-13', status: 'present' },
      { date: '2026-07-15', status: 'late' },
      { date: '2026-07-20', status: 'present' }, // next Monday
    ])
    expect(points).toEqual([
      { weekStart: '2026-07-13', attendancePct: 100, totalRecords: 2 },
      { weekStart: '2026-07-20', attendancePct: 100, totalRecords: 1 },
    ])
  })
})

describe('zero-denominator percentage', () => {
  it('returns 0 rather than NaN or Infinity', () => {
    expect(attendancePct(0, 0)).toBe(0)
    expect(attendancePct(3, 0)).toBe(0)
    expect(attendancePct(1, 2)).toBe(50)
  })
})

describe('audit cursor validation', () => {
  const uuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
  const ts = '2026-07-20T10:00:00.000Z'

  it('accepts a well-formed timestamp|uuid cursor', () => {
    expect(parseAuditCursor(`${ts}|${uuid}`)).toEqual({ beforeAt: ts, beforeId: uuid })
  })

  it('rejects malformed timestamps, uuids, commas, or parentheses', () => {
    expect(parseAuditCursor(`${ts},${uuid}`)).toBeNull()
    expect(parseAuditCursor(`not-a-date|${uuid}`)).toBeNull()
    expect(parseAuditCursor(`${ts}|not-a-uuid`)).toBeNull()
    expect(parseAuditCursor(`2026-07-20T10:00:00(Z)|${uuid}`)).toBeNull()
    expect(parseAuditCursor(undefined)).toBeNull()
  })
})

describe('audit entity labels', () => {
  it('falls back when referenced names are missing', () => {
    const row = {
      table_name: 'sessions',
      record_id: '12345678-aaaa-bbbb-cccc-dddddddddddd',
      new_data: { class_id: 'missing-class', session_date: '2026-07-20' },
      old_data: null,
    }
    expect(auditEntityLabel(row, new Map(), new Map())).toBe('sessions 12345678')
  })

  it('uses class and student names when present', () => {
    const classes = new Map([['c1', 'P4 Math']])
    const students = new Map([['s1', 'Ava']])
    expect(
      auditEntityLabel(
        {
          table_name: 'attendance_records',
          record_id: 'r1',
          new_data: { student_id: 's1', status: 'late' },
        },
        classes,
        students,
      ),
    ).toBe('Attendance: Ava (late)')
  })
})
