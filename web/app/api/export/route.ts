import JSZip from 'jszip'
import { createClient } from '@/lib/supabase/server'
import {
  exportFilename,
  filterStudySpaceData,
  toCsv,
  type ExportRow,
} from '@/lib/dashboard-export'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 60

const PAGE_SIZE = 1000

const FILES: Array<{ table: string; file: string; columns: string[] }> = [
  { table: 'students', file: 'students.csv', columns: ['id', 'full_name', 'date_of_birth', 'school', 'year_of_study', 'notes', 'avatar_url', 'is_active', 'created_at', 'updated_at', 'deactivated_at', 'created_by'] },
  { table: 'profiles', file: 'staff_profiles.csv', columns: ['id', 'full_name', 'role', 'phone', 'created_at', 'updated_at'] },
  { table: 'classes', file: 'classes.csv', columns: ['id', 'name', 'subject', 'level', 'schedule_day', 'schedule_time', 'duration_minutes', 'recurrence_rule', 'recurrence_end_date', 'is_active', 'is_study_space', 'created_at', 'updated_at'] },
  { table: 'class_tutor_assignments', file: 'class_tutor_assignments.csv', columns: ['id', 'class_id', 'tutor_id', 'assigned_from', 'assigned_until'] },
  { table: 'enrollments', file: 'enrollments.csv', columns: ['id', 'student_id', 'class_id', 'enrolled_at', 'unenrolled_at', 'is_active'] },
  { table: 'sessions', file: 'sessions.csv', columns: ['id', 'class_id', 'session_date', 'start_time', 'end_time', 'topic', 'notes', 'created_at', 'created_by', 'sub_tutor_id', 'started_at', 'ended_at'] },
  { table: 'attendance_records', file: 'attendance_records.csv', columns: ['id', 'session_id', 'student_id', 'status', 'marked_by', 'marked_at', 'notes', 'late_reason', 'client_mutation_id'] },
  { table: 'student_results', file: 'student_results.csv', columns: ['id', 'student_id', 'subject', 'grade', 'updated_by', 'created_at', 'updated_at'] },
  { table: 'awards', file: 'awards.csv', columns: ['id', 'student_id', 'award_type', 'period', 'awarded_at', 'awarded_by'] },
  { table: 'dismissals', file: 'dismissals.csv', columns: ['id', 'session_id', 'student_id', 'dismissed_at', 'dismissed_by', 'safely_home_at', 'confirmed_by'] },
  { table: 'parent_student_links', file: 'parent_student_links.csv', columns: ['id', 'parent_id', 'student_id', 'relationship', 'created_at'] },
  { table: 'consent_records', file: 'consent_records.csv', columns: ['id', 'student_id', 'consent_type', 'status', 'method', 'notice_version', 'parent_id', 'granted_by', 'source_note', 'created_at'] },
  { table: 'correction_requests', file: 'correction_requests.csv', columns: ['id', 'student_id', 'requested_by', 'field_name', 'current_value', 'requested_value', 'status', 'reviewed_by', 'reviewed_at', 'review_note', 'created_at'] },
  { table: 'result_slips', file: 'result_slips.csv', columns: ['id', 'student_id', 'exam_name', 'exam_date', 'subject', 'score', 'max_score', 'file_path', 'uploaded_by', 'uploaded_at', 'acknowledged_by', 'acknowledged_at'] },
  { table: 'messages', file: 'messages.csv', columns: ['id', 'sender_id', 'recipient_id', 'student_id', 'subject', 'body', 'sent_at', 'read_at'] },
  { table: 'audit_log', file: 'audit_log.csv', columns: ['id', 'table_name', 'record_id', 'action', 'old_data', 'new_data', 'changed_by', 'changed_at'] },
  { table: 'app_events', file: 'app_events.csv', columns: ['id', 'occurred_at', 'user_id', 'role', 'platform', 'app_version', 'session_id', 'event_type', 'name', 'properties', 'device'] },
  { table: 'data_disclosures', file: 'data_disclosures.csv', columns: ['id', 'student_id', 'disclosed_to', 'disclosure_type', 'disclosed_by', 'disclosed_at', 'detail'] },
  { table: 'policy_documents', file: 'policy_documents.csv', columns: ['id', 'doc_type', 'version', 'title', 'body', 'is_current', 'published_at', 'created_at'] },
  { table: 'feature_flags', file: 'feature_flags.csv', columns: ['key', 'enabled', 'description', 'updated_at'] },
]

async function fetchAll(supabase: Awaited<ReturnType<typeof createClient>>, table: string): Promise<ExportRow[]> {
  const rows: ExportRow[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await supabase.from(table).select('*').range(from, from + PAGE_SIZE - 1)
    if (error) throw new Error(`Could not export ${table}.`)
    const page = (data ?? []) as ExportRow[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new Response('Authentication required.', { status: 401 })

  const { data: isSuperadmin, error: permissionError } = await supabase.rpc('is_superadmin')
  if (permissionError || isSuperadmin !== true) return new Response('Not authorized.', { status: 403 })

  try {
    const datasets = Object.fromEntries(await Promise.all(
      FILES.map(async ({ table }) => [table, await fetchAll(supabase, table)]),
    )) as Record<string, ExportRow[]>
    const filtered = filterStudySpaceData({
      classes: datasets.classes,
      sessions: datasets.sessions,
      attendanceRecords: datasets.attendance_records,
      dismissals: datasets.dismissals,
      enrollments: datasets.enrollments,
      tutorAssignments: datasets.class_tutor_assignments,
      auditLog: datasets.audit_log,
    })

    datasets.classes = filtered.classes
    datasets.sessions = filtered.sessions
    datasets.attendance_records = filtered.attendanceRecords
    datasets.dismissals = filtered.dismissals
    datasets.enrollments = filtered.enrollments
    datasets.class_tutor_assignments = filtered.tutorAssignments
    datasets.audit_log = filtered.auditLog

    const zip = new JSZip()
    const generatedAt = new Date().toISOString()
    const manifest = FILES.map(({ file, table }) => ({
      file,
      table,
      row_count: datasets[table].length,
      generated_at: generatedAt,
      timezone: 'Asia/Singapore',
      study_space_excluded: ['classes', 'class_tutor_assignments', 'enrollments', 'sessions', 'attendance_records', 'dismissals', 'audit_log'].includes(table),
    }))
    zip.file('manifest.csv', toCsv(manifest, ['file', 'table', 'row_count', 'generated_at', 'timezone', 'study_space_excluded']))
    for (const { table, file, columns } of FILES) {
      zip.file(file, toCsv(datasets[table], columns))
    }

    const archive = await zip.generateAsync({ type: 'arraybuffer', compression: 'DEFLATE' })
    return new Response(archive, {
      headers: {
        'Content-Type': 'application/zip',
        'Content-Disposition': `attachment; filename="${exportFilename()}"`,
        'Cache-Control': 'private, no-store, max-age=0',
        'X-Content-Type-Options': 'nosniff',
      },
    })
  } catch {
    return new Response('The export could not be generated. Please try again.', { status: 500 })
  }
}
