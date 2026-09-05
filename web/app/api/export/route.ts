import JSZip from 'jszip'
import { EXPORT_FILES, fetchExportRows, fetchStudySpaceReferences } from '@/lib/queries/dashboard-export'
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

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new Response('Authentication required.', { status: 401 })

  const { data: isSuperadmin, error: permissionError } = await supabase.rpc('is_superadmin')
  if (permissionError || isSuperadmin !== true) return new Response('Not authorized.', { status: 403 })

  try {
    const [entries, studySpace] = await Promise.all([
      Promise.all(EXPORT_FILES.map(async file => [file.table, await fetchExportRows(supabase, file)])),
      fetchStudySpaceReferences(supabase),
    ])
    const datasets = Object.fromEntries(entries) as Record<string, ExportRow[]>
    const filtered = filterStudySpaceData({
      classes: [...datasets.classes, ...studySpace.classes],
      sessions: [...datasets.sessions, ...studySpace.sessions],
      attendanceRecords: [...datasets.attendance_records, ...studySpace.attendanceRecords],
      dismissals: [...datasets.dismissals, ...studySpace.dismissals],
      enrollments: [...datasets.enrollments, ...studySpace.enrollments],
      tutorAssignments: [...datasets.class_tutor_assignments, ...studySpace.tutorAssignments],
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
    const manifest = EXPORT_FILES.map(({ file, table }) => ({
      file,
      table,
      row_count: datasets[table].length,
      generated_at: generatedAt,
      timezone: 'Asia/Singapore',
      study_space_excluded: ['classes', 'class_tutor_assignments', 'enrollments', 'sessions', 'attendance_records', 'dismissals', 'audit_log'].includes(table),
    }))
    zip.file('manifest.csv', toCsv(manifest, ['file', 'table', 'row_count', 'generated_at', 'timezone', 'study_space_excluded']))
    for (const { table, file, columns } of EXPORT_FILES) {
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
