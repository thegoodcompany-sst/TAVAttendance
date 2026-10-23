import { beforeEach, expect, it, vi } from 'vitest'
const mocks = vi.hoisted(() => ({ client: vi.fn(), admin: vi.fn(), flag: vi.fn() }))
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))
vi.mock('@/lib/admin', () => ({ NRIC_RE: /unused/ }))
vi.mock('@/lib/feature-flags', () => ({ isFeatureEnabled: mocks.flag }))
vi.mock('@/lib/supabase/server', () => ({ createClient: mocks.client }))
vi.mock('@/lib/supabase/admin', () => ({ createAdminClient: mocks.admin }))
import { finalizeResultSlipUpload } from '../app/actions/parent-portal'
const studentId = '11111111-1111-4111-a111-111111111111'
const upload = { path: `${studentId}/test.pdf`, fileType: 'application/pdf', fileSize: 8,
  examName: 'Exam', subject: null, score: null, maxScore: null }
let intent: Record<string, unknown>
let persisted: Record<string, unknown> | null
let slots: Set<string>
let databaseError: boolean
const download = vi.fn(), list = vi.fn(), remove = vi.fn(), rpc = vi.fn()
beforeEach(() => {
  vi.clearAllMocks()
  intent = { expected_size: 8, expected_mime: 'application/pdf',
    expires_at: new Date(Date.now() + 3600000).toISOString(), finalized_at: null, finalized_result_id: null }
  persisted = null
  slots = new Set()
  databaseError = false
  mocks.flag.mockResolvedValue(true)
  mocks.client.mockResolvedValue({ auth: { getUser: async () => ({ data: { user: { id: 'parent' } } }) },
    rpc: async () => ({ data: [{ id: studentId }] }) })
  const from = (table: string) => {
    const filters: Record<string, unknown> = {}
    const query = {
      select: () => query, is: () => query, limit: () => query, delete: () => query,
      eq: (key: string, value: unknown) => { filters[key] = value; return query },
      lt: async () => ({ error: null }),
      maybeSingle: async () => ({ data: table === 'result_slip_upload_intents'
        ? (filters.actor_id === 'parent' && filters.student_id === studentId ? { ...intent } : null)
        : persisted, error: null }),
      insert: async ({ id }: { id: string }) => {
        if (databaseError) return { error: { code: '08006' } }
        if (slots.has(id)) return { error: { code: '23505' } }
        slots.add(id)
        return { error: null }
      },
    }
    return query
  }
  list.mockResolvedValue({ data: [{ id: 'object', name: 'test.pdf', metadata: { size: 8, mimetype: 'application/pdf' } }] })
  download.mockResolvedValue({ data: new Blob(['%PDF-abc']) })
  rpc.mockResolvedValue({ error: null })
  mocks.admin.mockResolvedValue({ from, rpc, storage: { from: () => ({ list, download, remove }) } })
})
it('retries finalized uploads through the exact-match RPC without Storage or quota work', async () => {
  intent.finalized_at = new Date().toISOString()
  intent.finalized_result_id = 'result'
  download.mockResolvedValue({ error: new Error('transient failure') })
  for (let i = 0; i < 3; i++) expect(await finalizeResultSlipUpload(studentId, upload)).toEqual({ error: null })
  expect(rpc).toHaveBeenCalledTimes(3)
  expect(list).not.toHaveBeenCalled()
  expect(download).not.toHaveBeenCalled()
  expect(remove).not.toHaveBeenCalled()
  expect(slots.size).toBe(0)
})
it('does not recreate an erased finalized result', async () => {
  intent.finalized_at = new Date().toISOString()
  expect((await finalizeResultSlipUpload(studentId, upload)).error).toMatch(/consumed/)
  expect(list).not.toHaveBeenCalled()
  expect(rpc).not.toHaveBeenCalled()
})
it('does not accept changed metadata as an exact retry after an RPC error', async () => {
  intent.finalized_at = new Date().toISOString()
  intent.finalized_result_id = 'result'
  persisted = { id: 'result', exam_name: 'Original exam', subject: null, score: null, max_score: null }
  rpc.mockResolvedValue({ error: new Error('already consumed') })
  expect((await finalizeResultSlipUpload(studentId, upload)).error).toMatch(/Could not save/)
  expect(download).not.toHaveBeenCalled()
})
it('recovers an exact commit after a lost RPC response', async () => {
  persisted = { id: 'result', exam_name: 'Exam', subject: null, score: null, max_score: null }
  rpc.mockResolvedValue({ error: new Error('lost response') })
  expect(await finalizeResultSlipUpload(studentId, upload)).toEqual({ error: null })
  expect(download).toHaveBeenCalledOnce()
})
it('allows retry after a transient download failure without deleting the object', async () => {
  download.mockResolvedValueOnce({ error: new Error('transient failure') })
  expect((await finalizeResultSlipUpload(studentId, upload)).error).toMatch(/try again/)
  expect(rpc).not.toHaveBeenCalled()
  expect(await finalizeResultSlipUpload(studentId, upload)).toEqual({ error: null })
  expect(remove).not.toHaveBeenCalled()
})
it.each(['metadata', 'signature'])('leaves %s rejection cleanup to the expiry worker', async kind => {
  if (kind === 'metadata') list.mockResolvedValue({ data: [] })
  else download.mockResolvedValue({ data: new Blob(['invalid!']) })
  expect((await finalizeResultSlipUpload(studentId, upload)).error).not.toBeNull()
  expect(remove).not.toHaveBeenCalled()
  expect(rpc).not.toHaveBeenCalled()
})
it('bounds simultaneous unfinalized retries to three downloads', async () => {
  download.mockResolvedValue({ error: new Error('transient failure') })
  const results = await Promise.all(Array.from({ length: 12 }, () => finalizeResultSlipUpload(studentId, upload)))
  expect(download).toHaveBeenCalledTimes(3)
  expect(results.filter(result => result.error?.includes('limit'))).toHaveLength(9)
  expect(remove).not.toHaveBeenCalled()
  expect(rpc).not.toHaveBeenCalled()
  expect((await finalizeResultSlipUpload(studentId, upload)).error).toMatch(/limit/)
  expect(download).toHaveBeenCalledTimes(3)
})
it('fails closed when the durable attempt claim fails', async () => {
  databaseError = true
  expect((await finalizeResultSlipUpload(studentId, upload)).error).toMatch(/unavailable/)
  expect(list).not.toHaveBeenCalled()
})
it('checks ownership before privileged work', async () => {
  mocks.client.mockResolvedValue({ auth: { getUser: async () => ({ data: { user: { id: 'other' } } }) },
    rpc: async () => ({ data: [] }) })
  expect((await finalizeResultSlipUpload(studentId, upload)).error).toBe('Not authorized.')
  expect(mocks.admin).not.toHaveBeenCalled()
})
