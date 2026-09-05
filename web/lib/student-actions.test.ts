import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc, requireAdmin } = vi.hoisted(() => ({ rpc: vi.fn(), requireAdmin: vi.fn() }))
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))
vi.mock('@/lib/admin', () => ({ requireAdmin, NRIC_RE: /\b[STFGM][0-9]{7}[A-Z]\b/i }))
vi.mock('@/lib/storage-cleanup', () => ({}))
vi.mock('@/lib/supabase/admin', () => ({}))
import { bulkImportStudents, createStudent, type StudentInput } from '../app/actions/students'

beforeEach(() => {
  vi.clearAllMocks()
  requireAdmin.mockResolvedValue({ error: null, supabase: { rpc } })
  rpc.mockResolvedValue({ error: null })
})

describe('student action input boundary', () => {
  it('rejects truthy non-boolean consent without writing', async () => {
    const consent = 'false' as unknown as boolean
    expect((await createStudent({ fullName: 'Example Student' }, consent)).error).toMatch(/consent/)
    expect((await bulkImportStudents([{ fullName: 'Example Student' }], consent)).error).toMatch(/consent/)
    expect(rpc).not.toHaveBeenCalled()
  })

  it('rejects malformed single-student input without throwing', async () => {
    for (const input of [null, { fullName: 42 }, { fullName: 'Example Student', notes: [] }]) {
      expect((await createStudent(input as unknown as StudentInput, true)).error).toMatch(/text/)
    }
    expect(rpc).not.toHaveBeenCalled()
  })

  it('reports malformed rows after successful rows without losing the import result', async () => {
    const rows = [{ fullName: 'Example Student' }, null, { fullName: 'Another Student', school: 42 }]
    expect(await bulkImportStudents(rows as unknown as StudentInput[], true)).toEqual({
      error: null,
      created: 1,
      skipped: [
        { row: 2, reason: 'Student fields must be text' },
        { row: 3, reason: 'Student fields must be text' },
      ],
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('requires admin authorization before any import', async () => {
    requireAdmin.mockResolvedValue({ error: 'Only admins can perform this action.' })
    expect((await bulkImportStudents([{ fullName: 'Example Student' }], true)).error).toMatch(/admins/)
    expect(rpc).not.toHaveBeenCalled()
  })
})
