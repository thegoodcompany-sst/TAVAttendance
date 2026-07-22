export type ExportRow = Record<string, unknown>

const FORMULA_PREFIX = /^[\t\r ]*[=+\-@]/

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

export function toCsv(rows: ExportRow[], fallbackColumns: string[] = []): string {
  const columns = [...fallbackColumns]
  for (const row of rows) {
    for (const key of Object.keys(row)) {
      if (!columns.includes(key)) columns.push(key)
    }
  }

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
  const studyClassIds = new Set(
    classes.filter(row => row.is_study_space === true).map(row => String(row.id)),
  )
  const visibleClasses = classes.filter(row => !studyClassIds.has(String(row.id)))
  const studySessionIds = new Set(
    sessions.filter(row => studyClassIds.has(String(row.class_id))).map(row => String(row.id)),
  )
  const visibleSessions = sessions.filter(row => !studySessionIds.has(String(row.id)))
  const studyAttendanceIds = new Set(
    attendanceRecords
      .filter(row => studySessionIds.has(String(row.session_id)))
      .map(row => String(row.id)),
  )
  const visibleAttendance = attendanceRecords.filter(row => !studyAttendanceIds.has(String(row.id)))
  const studyDismissalIds = new Set(
    dismissals
      .filter(row => studySessionIds.has(String(row.session_id)))
      .map(row => String(row.id)),
  )

  const snapshotFor = (row: ExportRow) => (row.new_data ?? row.old_data ?? {}) as ExportRow
  const auditStudySessionIds = new Set([
    ...studySessionIds,
    ...auditLog
      .filter(row => row.table_name === 'sessions' && studyClassIds.has(String(snapshotFor(row).class_id)))
      .map(row => String(row.record_id)),
  ])
  const auditStudyAttendanceIds = new Set([
    ...studyAttendanceIds,
    ...auditLog
      .filter(row => row.table_name === 'attendance_records' && auditStudySessionIds.has(String(snapshotFor(row).session_id)))
      .map(row => String(row.record_id)),
  ])
  const auditStudyDismissalIds = new Set([
    ...studyDismissalIds,
    ...auditLog
      .filter(row => row.table_name === 'dismissals' && auditStudySessionIds.has(String(snapshotFor(row).session_id)))
      .map(row => String(row.record_id)),
  ])

  const auditReferencesStudySpace = (row: ExportRow) => {
    const snapshot = snapshotFor(row)
    const recordId = String(row.record_id)
    if (row.table_name === 'classes' && snapshot.is_study_space === true) return true
    if (studyClassIds.has(String(snapshot.class_id))) return true
    if (auditStudySessionIds.has(String(snapshot.session_id))) return true

    switch (row.table_name) {
      case 'classes': return studyClassIds.has(recordId)
      case 'sessions': return auditStudySessionIds.has(recordId)
      case 'attendance_records': return auditStudyAttendanceIds.has(recordId)
      case 'dismissals': return auditStudyDismissalIds.has(recordId)
      case 'enrollments': return studyClassIds.has(String(snapshot.class_id))
      case 'class_tutor_assignments': return studyClassIds.has(String(snapshot.class_id))
      default: return false
    }
  }

  return {
    classes: visibleClasses,
    sessions: visibleSessions,
    attendanceRecords: visibleAttendance,
    dismissals: dismissals.filter(row => !studyDismissalIds.has(String(row.id))),
    enrollments: enrollments.filter(row => !studyClassIds.has(String(row.class_id))),
    tutorAssignments: tutorAssignments.filter(row => !studyClassIds.has(String(row.class_id))),
    auditLog: auditLog.filter(row => !auditReferencesStudySpace(row)),
  }
}
