import type { DemoJournal } from './journal'
import type { DemoTables } from './seed'

// These are demo persistence limits, independent of the compressed cookie size.
export const MAX_TABLE_ROWS = 256
export const MAX_JOURNAL_ROWS = 1024
const unsafeKeys = new Set(['__proto__', 'prototype', 'constructor'])
const id = (value: unknown): value is string => typeof value === 'string'
  && value.length > 0 && value.length <= 128 && !unsafeKeys.has(value)
const object = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value)

// Missing optional columns are allowed: inserts do not populate every column.
// Values are scalar except the explicitly bounded audit snapshots.
const columns: Record<string, string> = {
  profiles: 'full_name role phone created_at',
  classes: 'name subject level schedule_day schedule_time duration_minutes is_active recurrence_rule recurrence_end_date is_study_space created_at',
  students: 'full_name school year_of_study is_active avatar_url notes date_of_birth created_at',
  enrollments: 'student_id class_id is_active enrolled_at unenrolled_at',
  class_tutor_assignments: 'class_id tutor_id assigned_until created_at',
  sessions: 'class_id session_date topic notes started_at ended_at sub_tutor_id created_at',
  attendance_records: 'session_id student_id status marked_at marked_by notes late_reason absence_informed client_mutation_id',
  student_results: 'student_id subject grade updated_by updated_at created_at',
  result_slips: 'student_id exam_name exam_date subject score max_score file_path uploaded_by uploaded_at acknowledged_at acknowledged_by',
  messages: 'sender_id recipient_id student_id subject body sent_at read_at',
  parent_student_links: 'parent_id student_id created_at',
  awards: 'student_id award_type period awarded_at awarded_by',
  correction_requests: 'student_id requested_by field_name current_value requested_value status reviewed_by reviewed_at review_note created_at',
  consent_records: 'student_id consent_type status method notice_version granted_by parent_id source_note created_at',
  policy_documents: 'doc_type version title body is_current published_at',
  feature_flags: 'key enabled description updated_at',
  audit_log: 'table_name record_id action old_data new_data changed_by changed_at',
  nfc_chip_bindings: 'student_id chip_uid chip_uid_suffix issued_at revoked_at',
  // The emulator does not persist writes to these tables.
  result_slip_upload_intents: '', app_events: '', dismissals: '', student_storage_cleanup_queue: '',
}
const booleans = new Set(['is_active', 'is_study_space', 'absence_informed', 'is_current', 'enabled'])
const numbers = new Set(['duration_minutes', 'score', 'max_score'])
const unique: Record<string, string[]> = {
  sessions: ['class_id', 'session_date'],
  enrollments: ['class_id', 'student_id'],
  attendance_records: ['session_id', 'student_id'],
  class_tutor_assignments: ['class_id', 'tutor_id'],
  parent_student_links: ['parent_id', 'student_id'],
  student_results: ['student_id', 'subject'],
  feature_flags: ['key'],
}

function validRow(table: string, key: string, row: unknown): boolean {
  if (!object(row) || !id(key) || row.id !== key || !columns[table]) return false
  const allowed = new Set(['id', ...columns[table].split(' ')])
  for (const [field, value] of Object.entries(row)) {
    if (!allowed.has(field)) return false
    if (value === null) continue
    if (booleans.has(field)) { if (typeof value !== 'boolean') return false }
    else if (numbers.has(field)) { if (typeof value !== 'number' || !Number.isFinite(value)) return false }
    else if (table === 'audit_log' && (field === 'old_data' || field === 'new_data')) {
      if (!object(value) || Object.keys(value).length > 32 || Object.entries(value).some(([k, v]) =>
        unsafeKeys.has(k) || !(v === null || typeof v === 'boolean' || typeof v === 'number'
          || (typeof v === 'string' && v.length <= 4096)))) return false
    } else if (typeof value !== 'string' || value.length > 4096) return false
    if ((field === 'id' || field.endsWith('_id')) && !id(value)) return false
  }
  if (unique[table]?.some(field => !id(row[field]))) return false
  if (table === 'sessions' && (typeof row.session_date !== 'string'
    || !/^\d{4}-\d{2}-\d{2}$/.test(row.session_date)
    || !Number.isFinite(Date.parse(row.session_date))
    || new Date(row.session_date).toISOString().slice(0, 10) !== row.session_date)) return false
  if (table === 'attendance_records' && !['present', 'late', 'absent'].includes(row.status as string)) return false
  return true
}

export function validJournal(value: unknown): value is DemoJournal {
  if (!object(value) || value.v !== 1 || !object(value.t)
    || Object.keys(value).some(key => key !== 'v' && key !== 't')) return false
  let total = 0
  for (const [table, entry] of Object.entries(value.t)) {
    if (!Object.hasOwn(columns, table) || !object(entry) || !object(entry.u) || !Array.isArray(entry.d)
      || Object.keys(entry).some(key => key !== 'u' && key !== 'd')) return false
    const rows = Object.entries(entry.u)
    const count = rows.length + entry.d.length
    total += count
    if (count > MAX_TABLE_ROWS || total > MAX_JOURNAL_ROWS || !entry.d.every(id)
      || new Set(entry.d).size !== entry.d.length) return false
    const keys = new Set<string>()
    for (const [key, row] of rows) {
      if (!validRow(table, key, row) || entry.d.includes(key)) return false
      if (unique[table]) {
        const domainKey = JSON.stringify(unique[table].map(field => (row as Record<string, unknown>)[field]))
        if (keys.has(domainKey)) return false
        keys.add(domainKey)
      }
    }
  }
  return true
}

/** Check the merged state too: a journal may conflict with untouched seed rows. */
export function validDemoTables(tables: DemoTables): boolean {
  let total = 0
  for (const [table, rows] of Object.entries(tables)) {
    total += rows.length
    if (rows.length > MAX_TABLE_ROWS || total > MAX_JOURNAL_ROWS) return false
    const keys = new Set<string>()
    for (const row of rows) {
      const key = JSON.stringify(unique[table] ? unique[table].map(field => row[field]) : [row.id])
      if (keys.has(key)) return false
      keys.add(key)
    }
  }
  return true
}
