import { describe, expect, it, vi } from 'vitest'
import { EXPORT_FILES, fetchExportRows, fetchStudySpaceReferences } from './dashboard-export'

function clientFor(pages: Array<{ data: Record<string, unknown>[] | null; error: unknown }>) {
  const query = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    in: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    range: vi.fn().mockReturnThis(),
    overrideTypes: vi.fn(),
  }
  for (const page of pages) query.overrideTypes.mockResolvedValueOnce(page)
  const from = vi.fn().mockReturnValue(query)
  return { query, from, client: { from } as unknown as Parameters<typeof fetchExportRows>[0] }
}

describe('dashboard export queries', () => {
  it('paginates using a unique order and an explicit column projection', async () => {
    const firstPage = Array.from({ length: 1000 }, (_, id) => ({ id: String(id) }))
    const { client, query } = clientFor([
      { data: firstPage, error: null },
      { data: [{ id: '1000' }], error: null },
    ])
    const rows = await fetchExportRows(client, { table: 'students', columns: ['id', 'full_name'] })
    expect(rows).toHaveLength(1001)
    expect(query.select).toHaveBeenNthCalledWith(1, 'id,full_name')
    expect(query.order).toHaveBeenNthCalledWith(1, 'id', { ascending: true })
    expect(query.order).toHaveBeenNthCalledWith(2, 'id', { ascending: true })
    expect(query.range).toHaveBeenNthCalledWith(1, 0, 999)
    expect(query.range).toHaveBeenNthCalledWith(2, 1000, 1999)
  })

  it.each([
    ['classes', 'is_study_space', 'id'],
    ['sessions', 'class.is_study_space', 'id,class:classes!inner(is_study_space)'],
    ['enrollments', 'class.is_study_space', 'id,class:classes!inner(is_study_space)'],
    ['class_tutor_assignments', 'class.is_study_space', 'id,class:classes!inner(is_study_space)'],
    ['attendance_records', 'session.class.is_study_space', 'id,session:sessions!inner(class:classes!inner(is_study_space))'],
    ['dismissals', 'session.class.is_study_space', 'id,session:sessions!inner(class:classes!inner(is_study_space))'],
  ])('excludes Study Space at the source for %s', async (table, filter, projection) => {
    const { client, query } = clientFor([{ data: [], error: null }])
    await fetchExportRows(client, { table, columns: ['id'] })
    expect(query.select).toHaveBeenCalledWith(projection)
    expect(query.eq).toHaveBeenCalledWith(filter, false)
  })

  it('fetches internal identities to exclude audit rows even without snapshots', async () => {
    const { client, query } = clientFor([
      { data: [{ id: 'study', is_study_space: true }], error: null },
      { data: [{ id: 'study-session', class_id: 'study' }], error: null },
      { data: [{ id: 'study-attendance', session_id: 'study-session' }], error: null },
      { data: [{ id: 'study-dismissal', session_id: 'study-session' }], error: null },
      { data: [{ id: 'study-enrollment', class_id: 'study' }], error: null },
      { data: [{ id: 'study-assignment', class_id: 'study' }], error: null },
    ])
    const references = await fetchStudySpaceReferences(client)
    expect(query.select).toHaveBeenNthCalledWith(1, 'id,is_study_space')
    expect(query.select).toHaveBeenNthCalledWith(2, 'id,class_id,class:classes!inner(is_study_space)')
    expect(query.eq).toHaveBeenCalledWith('is_study_space', true)
    expect(query.eq).toHaveBeenCalledWith('class.is_study_space', true)
    expect(references.sessions).toEqual([{ id: 'study-session', class_id: 'study' }])
    expect(query.eq).toHaveBeenCalledWith('session.class.is_study_space', true)
    const { filterStudySpaceData } = await import('../dashboard-export')
    const filtered = filterStudySpaceData({ ...references, auditLog: [
      { table_name: 'attendance_records', record_id: 'study-attendance' },
      { table_name: 'dismissals', record_id: 'study-dismissal' },
      { table_name: 'enrollments', record_id: 'study-enrollment' },
      { table_name: 'class_tutor_assignments', record_id: 'study-assignment' },
    ] })
    expect(filtered.auditLog).toEqual([])
    expect(filtered.attendanceRecords).toEqual([])
    expect(filtered.dismissals).toEqual([])
  })

  it('limits the staff export to staff roles at the source', async () => {
    const { client, query } = clientFor([{ data: [], error: null }])
    await fetchExportRows(client, EXPORT_FILES.find(file => file.table === 'profiles')!)
    expect(query.in).toHaveBeenCalledWith('role', ['admin', 'tutor'])
  })

  it('orders feature flags by their key rather than a nonexistent id', async () => {
    const { client, query } = clientFor([{ data: [], error: null }])
    await fetchExportRows(client, EXPORT_FILES.find(file => file.table === 'feature_flags')!)
    expect(query.order).toHaveBeenCalledWith('key', { ascending: true })
  })

  it('fails the export rather than returning a partial dataset after a query error', async () => {
    const { client } = clientFor([{ data: null, error: { message: 'database failure' } }])
    await expect(fetchExportRows(client, { table: 'students', columns: ['id'] }))
      .rejects.toThrow('Could not export students.')
  })
})
