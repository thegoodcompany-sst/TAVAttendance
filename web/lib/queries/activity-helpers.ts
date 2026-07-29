/* eslint-disable @typescript-eslint/no-explicit-any */

const AUDIT_COLUMN_LABEL: Record<string, string> = {
  schedule_time: 'schedule',
  schedule_day: 'day',
  recurrence_rule: 'recurrence',
  full_name: 'name',
  session_date: 'date',
  late_reason: 'late reason',
  marked_at: 'marked time',
  is_active: 'active',
  class_id: 'class',
  student_id: 'student',
}

/** Validates audit pagination cursor (`changed_at|uuid`). Returns null when rejected. */
export function parseAuditCursor(before: string | undefined): { beforeAt: string; beforeId: string } | null {
  if (!before) return null
  const separator = before.lastIndexOf('|')
  const beforeAt = before.slice(0, separator)
  const beforeId = before.slice(separator + 1)
  const isoOk =
    /^\d{4}-\d{2}-\d{2}T[\d:.+-Z]+$/.test(beforeAt) &&
    !beforeAt.includes(',') &&
    !beforeAt.includes('(') &&
    !beforeAt.includes(')') &&
    !Number.isNaN(Date.parse(beforeAt))
  if (
    separator > 0 &&
    isoOk &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(beforeId)
  ) {
    return { beforeAt, beforeId }
  }
  return null
}

export function auditDetail(row: any): string {
  if (row.action !== 'UPDATE') return ''
  const oldData = row.old_data ?? {}
  const newData = row.new_data ?? {}
  const keys = new Set([...Object.keys(oldData), ...Object.keys(newData)])
  const changed = [...keys]
    .filter(k => JSON.stringify(oldData[k]) !== JSON.stringify(newData[k]))
    .map(k => AUDIT_COLUMN_LABEL[k] ?? k)
  if (!changed.length) return ''
  return `Changed ${changed.slice(0, 5).join(', ')}${changed.length > 5 ? ` +${changed.length - 5}` : ''}`
}

export function auditEntityLabel(
  row: any,
  classNames: Map<string, string>,
  studentNames: Map<string, string>,
): string {
  const snap = (row.new_data ?? row.old_data ?? {}) as Record<string, any>
  const fallback = `${row.table_name} ${String(row.record_id).slice(0, 8)}`
  switch (row.table_name) {
    case 'students':
      return snap.full_name ? `Student: ${snap.full_name}` : fallback
    case 'classes':
      return snap.name ? `Class: ${snap.name}` : fallback
    case 'profiles':
      return snap.full_name ? `User: ${snap.full_name}` : fallback
    case 'sessions': {
      const name = classNames.get(snap.class_id)
      if (!name) return fallback
      return snap.session_date ? `Session: ${name} — ${snap.session_date}` : `Session: ${name}`
    }
    case 'enrollments': {
      const student = studentNames.get(snap.student_id)
      const cls = classNames.get(snap.class_id)
      if (!student && !cls) return fallback
      return `Enrolment: ${student ?? 'student'} in ${cls ?? 'class'}`
    }
    case 'attendance_records': {
      const student = studentNames.get(snap.student_id)
      if (!student) return fallback
      return snap.status ? `Attendance: ${student} (${snap.status})` : `Attendance: ${student}`
    }
    default:
      return fallback
  }
}

