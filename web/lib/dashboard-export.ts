export type ExportRow = Record<string, unknown>

const FORMULA_PREFIX = /^[\u0000-\u0020]*[=+\-@]/

export function csvCell(value: unknown): string {
  if (value === null || value === undefined) return ''

  const text = typeof value === 'string'
    ? value
    : typeof value === 'object'
      ? JSON.stringify(value)
      : String(value)
  const safeText = FORMULA_PREFIX.test(text) ? `'${text}` : text

  return /[",\r\n]/.test(safeText)
    ? `"${safeText.replaceAll('"', '""')}"`
    : safeText
}

export function toCsv(rows: ExportRow[], columns: string[]): string {
  if (columns.length === 0) return ''

  return [
    columns.map(csvCell).join(','),
    ...rows.map(row => columns.map(column => csvCell(row[column])).join(',')),
  ].join('\r\n') + '\r\n'
}

export function exportFilename(date = new Date()): string {
  return `tava-dashboard-export-${date.toISOString().slice(0, 10)}.zip`
}

export function filterStudySpaceData({
  classes,
  sessions,
  attendanceRecords,
  dismissals,
  enrollments,
  tutorAssignments,
  auditLog,
}: {
  classes: ExportRow[]
  sessions: ExportRow[]
  attendanceRecords: ExportRow[]
  dismissals: ExportRow[]
  enrollments: ExportRow[]
  tutorAssignments: ExportRow[]
  auditLog: ExportRow[]
}) {
  const snapshots = (row: ExportRow): ExportRow[] => [row.old_data, row.new_data]
    .filter((value): value is ExportRow => value !== null && typeof value === 'object' && !Array.isArray(value))
  const references = (row: ExportRow, field: string, ids: Set<string>) =>
    typeof row[field] === 'string' && ids.has(row[field] as string)

  // Retain identities from both snapshots, including records no longer in live tables.
  const excludedIds = (table: string, rows: ExportRow[], predicate: (row: ExportRow) => boolean) => {
    const ids = new Set<string>()
    for (const row of rows) {
      if (predicate(row) && typeof row.id === 'string') ids.add(row.id)
    }
    for (const row of auditLog) {
      if (row.table_name === table && snapshots(row).some(predicate) && typeof row.record_id === 'string') {
        ids.add(row.record_id)
      }
    }
    return ids
  }
  const studyClassIds = excludedIds('classes', classes, row => row.is_study_space === true)
  const studySessionIds = excludedIds('sessions', sessions, row => references(row, 'class_id', studyClassIds))
  const studyAttendanceIds = excludedIds('attendance_records', attendanceRecords, row => references(row, 'session_id', studySessionIds))
  const studyDismissalIds = excludedIds('dismissals', dismissals, row => references(row, 'session_id', studySessionIds))
  const studyEnrollmentIds = excludedIds('enrollments', enrollments, row => references(row, 'class_id', studyClassIds))
  const studyAssignmentIds = excludedIds('class_tutor_assignments', tutorAssignments, row => references(row, 'class_id', studyClassIds))
  const excludedByTable: Record<string, Set<string>> = {
    classes: studyClassIds,
    sessions: studySessionIds,
    attendance_records: studyAttendanceIds,
    dismissals: studyDismissalIds,
    enrollments: studyEnrollmentIds,
    class_tutor_assignments: studyAssignmentIds,
  }

  return {
    classes: classes.filter(row => !references(row, 'id', studyClassIds)),
    sessions: sessions.filter(row => !references(row, 'id', studySessionIds)),
    attendanceRecords: attendanceRecords.filter(row => !references(row, 'id', studyAttendanceIds)),
    dismissals: dismissals.filter(row => !references(row, 'id', studyDismissalIds)),
    enrollments: enrollments.filter(row => !references(row, 'id', studyEnrollmentIds)),
    tutorAssignments: tutorAssignments.filter(row => !references(row, 'id', studyAssignmentIds)),
    auditLog: auditLog.filter(row => {
      const ids = excludedByTable[String(row.table_name)]
      if (ids && references(row, 'record_id', ids)) return false
      return !snapshots(row).some(snapshot =>
        references(snapshot, 'class_id', studyClassIds) || references(snapshot, 'session_id', studySessionIds))
    }),
  }
}
