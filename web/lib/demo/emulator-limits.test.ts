import { describe, expect, it } from 'vitest'
import { createDemoClient } from './emulator'

describe('demo query expansion budget', () => {
  it('fails explicitly instead of returning a partial expanded result', async () => {
    let projections = 0
    const client = createDemoClient({
      now: () => 0,
      tables: {
        classes: [{ id: 'class' }],
        sessions: Array.from({ length: 100 }, (_, i) => ({ id: `s${i}`, class_id: 'class' })),
        enrollments: Array.from({ length: 100 }, (_, i) => ({
          id: `e${i}`, class_id: 'class',
          get is_active() { projections++; return true },
        })),
      },
    })
    const result = await client.from('sessions').select('id,classes(enrollments(is_active))')
    expect(result.data).toBeNull()
    expect(result.error?.message).toContain('Demo query expansion limit exceeded')
    expect(projections).toBeLessThanOrEqual(5000)
    // Each query gets a fresh budget.
    expect((await client.from('sessions').select('id')).error).toBeNull()
  })

  it('bounds relationship scans even when no children match', async () => {
    let scans = 0
    const client = createDemoClient({ now: () => 0, tables: {
      classes: Array.from({ length: 256 }, (_, i) => ({ id: `c${i}` })),
      enrollments: Array.from({ length: 500 }, (_, i) => ({
        id: `e${i}`, get class_id() { scans++; return 'missing' },
      })),
    } })
    const result = await client.from('classes').select('id,enrollments(id)')
    expect(result.data).toBeNull()
    expect(result.error?.message).toContain('Demo query expansion limit exceeded')
    expect(scans).toBeLessThanOrEqual(100000)
  })

  it('bounds projected bytes when large scalar values are embedded repeatedly', async () => {
    const client = createDemoClient({ now: () => 0, tables: {
      classes: [{ id: 'class', name: 'x'.repeat(4096) }],
      sessions: Array.from({ length: 256 }, (_, i) => ({ id: `s${i}`, class_id: 'class' })),
    } })
    const result = await client.from('sessions').select('id,classes(name)')
    expect(result.data).toBeNull()
    expect(result.error?.message).toContain('Demo query expansion limit exceeded')
  })
})
