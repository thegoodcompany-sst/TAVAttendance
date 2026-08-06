import { describe, expect, it } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { filterStudySpaceData } from './dashboard-export'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')

function readRepo(...parts: string[]): string {
  return readFileSync(path.join(repoRoot, ...parts), 'utf8')
}

/** Latest migration body that recreates `attendance_summary`. */
function latestAttendanceSummaryDefinition(): string {
  const dir = path.join(repoRoot, 'supabase/migrations')
  const files = readdirSync(dir)
    .filter((name) => name.endsWith('.sql'))
    .sort()
  let latest = ''
  for (const name of files) {
    const body = readFileSync(path.join(dir, name), 'utf8')
    if (/CREATE\s+VIEW\s+public\.attendance_summary/i.test(body)) {
      latest = body
    }
  }
  expect(latest, 'expected a migration to define attendance_summary').not.toBe('')
  const match = latest.match(
    /CREATE\s+VIEW\s+public\.attendance_summary[\s\S]*?;\s*(?:\n|$)/i,
  )
  expect(match, 'could not extract attendance_summary CREATE VIEW').toBeTruthy()
  return match![0]
}

describe('study-space exclusion contracts (shipped sources)', () => {
  it('attendance_summary view filters is_study_space = FALSE with security_invoker', () => {
    const view = latestAttendanceSummaryDefinition()
    expect(view).toMatch(/security_invoker\s*=\s*true/i)
    expect(view).toMatch(/c\.is_study_space\s*=\s*FALSE/i)
  })

  it('get_parent_attendance_summary in latest defining migration excludes study space', () => {
    // Migration 055 is the current definer for parent summary + view (repo tip).
    const mig = readRepo('supabase/migrations/055_merge_not_here_yet.sql')
    const fnStart = mig.indexOf('CREATE FUNCTION public.get_parent_attendance_summary')
    expect(fnStart).toBeGreaterThan(-1)
    const slice = mig.slice(fnStart, fnStart + 2500)
    expect(slice).toMatch(/c\.is_study_space\s*=\s*FALSE/i)
  })

  it('iOS staff history query uses StudentAttendanceHistoryQuery study-space filter', () => {
    const query = readRepo(
      'iOS/TAVAttendance/Services/StudentAttendanceHistoryQuery.swift',
    )
    const service = readRepo(
      'iOS/TAVAttendance/Services/AttendanceService+SessionsAttendance.swift',
    )
    expect(query).toContain('is_study_space')
    expect(query).toContain('session.class.is_study_space')
    expect(service).toContain('StudentAttendanceHistoryQuery.select')
    expect(service).toContain('StudentAttendanceHistoryQuery.studySpaceFilterColumn')
  })

  it('Android staff history query uses StudentAttendanceHistoryQuery study-space filter', () => {
    const query = readRepo(
      'Android/app/src/main/java/com/example/tavattendance/data/service/StudentAttendanceHistoryQuery.kt',
    )
    const service = readRepo(
      'Android/app/src/main/java/com/example/tavattendance/data/service/SessionAttendanceDataSource.kt',
    )
    // Filter excludes study space; SELECT stays name-only for ClassSummary decode
    // (absence_informed is on the attendance row, not nested under class).
    expect(query).toContain('session.class.is_study_space')
    expect(query).toMatch(
      /SELECT\s*=\s*"id, status, marked_at, absence_informed, session:sessions!inner\(session_date, class:classes!inner\(name\)\)"/,
    )
    expect(query).not.toMatch(
      /SELECT\s*=\s*"[^"]*is_study_space/,
    )
    expect(service).toContain('StudentAttendanceHistoryQuery.SELECT')
    expect(service).toContain('StudentAttendanceHistoryQuery.STUDY_SPACE_FILTER_COLUMN')
  })

  it('web staff year-history query excludes study space and selects absence_informed', () => {
    const src = readRepo('web/lib/queries/students.ts')
    expect(src).toContain('getStudentYearHistory')
    expect(src).toContain('session.class.is_study_space')
    expect(src).toContain('absence_informed')
    expect(src).not.toMatch(/from\('attendance_summary'\)/)
  })

  it('web parent queries do not select absence_informed', () => {
    const src = readRepo('web/lib/parent-queries.ts')
    expect(src).not.toContain('absence_informed')
  })

  it('web export helper still strips study-space related rows', () => {
    const result = filterStudySpaceData({
      classes: [
        { id: 'regular', is_study_space: false },
        { id: 'study', is_study_space: true },
      ],
      sessions: [
        { id: 'regular-session', class_id: 'regular' },
        { id: 'study-session', class_id: 'study' },
      ],
      attendanceRecords: [
        { id: 'regular-record', session_id: 'regular-session' },
        { id: 'study-record', session_id: 'study-session' },
      ],
      dismissals: [],
      enrollments: [],
      tutorAssignments: [],
      auditLog: [],
    })
    expect(result.classes).toHaveLength(1)
    expect(result.attendanceRecords).toHaveLength(1)
    expect(result.attendanceRecords[0].id).toBe('regular-record')
  })
})
