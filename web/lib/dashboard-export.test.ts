import { describe, expect, it } from 'vitest'
import JSZip from 'jszip'
import { csvCell, exportFilename, filterStudySpaceData, toCsv } from './dashboard-export'

describe('dashboard export CSV utilities', () => {
  it('escapes RFC-4180 special characters and serializes JSON', () => {
    expect(csvCell('A, "quoted"\nvalue')).toBe('"A, ""quoted""\nvalue"')
    expect(csvCell({ name: 'TAVA' })).toBe('"{""name"":""TAVA""}"')
  })

  it('neutralizes spreadsheet formulas', () => {
    expect(csvCell('=SUM(A1:A2)')).toBe("'=SUM(A1:A2)")
    expect(csvCell(' @cmd')).toBe("' @cmd")
  })

  it('emits headers for empty datasets', () => {
    expect(toCsv([], ['id', 'name'])).toBe('id,name\r\n')
  })

  it('uses a stable dated archive name', () => {
    expect(exportFilename(new Date('2026-07-22T12:00:00Z'))).toBe('tava-dashboard-export-2026-07-22.zip')
  })

  it('creates an archive that can be opened and read back', async () => {
    const zip = new JSZip()
    zip.file('students.csv', toCsv([{ id: '1', full_name: '李明' }], ['id', 'full_name']))
    const archive = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' })
    const reopened = await JSZip.loadAsync(archive)

    await expect(reopened.file('students.csv')?.async('string')).resolves.toBe('id,full_name\r\n1,李明\r\n')
  })
})

describe('Study Space filtering', () => {
  it('removes related attendance, class data, and audit records', () => {
    const result = filterStudySpaceData({
      classes: [{ id: 'regular', is_study_space: false }, { id: 'study', is_study_space: true }],
      sessions: [{ id: 'regular-session', class_id: 'regular' }, { id: 'study-session', class_id: 'study' }],
      attendanceRecords: [{ id: 'regular-record', session_id: 'regular-session' }, { id: 'study-record', session_id: 'study-session' }],
      dismissals: [{ id: 'regular-dismissal', session_id: 'regular-session' }, { id: 'study-dismissal', session_id: 'study-session' }],
      enrollments: [{ id: 'regular-enrollment', class_id: 'regular' }, { id: 'study-enrollment', class_id: 'study' }],
      tutorAssignments: [{ id: 'regular-assignment', class_id: 'regular' }, { id: 'study-assignment', class_id: 'study' }],
      auditLog: [
        { id: 'a', table_name: 'attendance_records', record_id: 'study-record' },
        { id: 'deleted-study-class', table_name: 'classes', record_id: 'deleted-study', old_data: { is_study_space: true } },
        { id: 'b', table_name: 'students', record_id: 'student' },
      ],
    })

    expect(result.classes).toHaveLength(1)
    expect(result.sessions).toHaveLength(1)
    expect(result.attendanceRecords).toHaveLength(1)
    expect(result.dismissals).toHaveLength(1)
    expect(result.enrollments).toHaveLength(1)
    expect(result.tutorAssignments).toHaveLength(1)
    expect(result.auditLog).toEqual([{ id: 'b', table_name: 'students', record_id: 'student' }])
  })
})
