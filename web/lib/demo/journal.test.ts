import { deflateRawSync } from 'node:zlib'
import { describe, expect, it } from 'vitest'
import { DEMO_STATE_MAX_CHUNKS } from './constants'
import { CHUNK_SIZE, decodeJournal, emptyJournal, encodeJournal, recordChange } from './journal'
import { buildDemoTables } from './seed'

describe('demo journal size limits', () => {
  it('round-trips a journal containing every seeded row plus a deletion', () => {
    const journal = emptyJournal()
    for (const [table, rows] of Object.entries(buildDemoTables(Date.UTC(2026, 9, 22)))) {
      recordChange(journal, { table, upserted: rows, deleted: [] })
    }
    recordChange(journal, { table: 'messages', upserted: [], deleted: ['removed-message'] })
    const encoded = encodeJournal(journal)
    expect(encoded.length).toBeLessThanOrEqual(CHUNK_SIZE * DEMO_STATE_MAX_CHUNKS)
    expect(decodeJournal(encoded)).toEqual(journal)
  })

  it('rejects a small cookie that expands to a multi-megabyte journal', () => {
    const journal = emptyJournal()
    recordChange(journal, {
      table: 'messages',
      upserted: [{ id: 'a', body: 'x'.repeat(2 * 1024 * 1024) }],
      deleted: [],
    })
    const encoded = encodeJournal(journal)
    expect(encoded.length).toBeLessThan(CHUNK_SIZE)
    expect(decodeJournal(encoded)).toEqual(emptyJournal())
  })

  it('rejects encoded input beyond the cookie budget even when decoded data is small', () => {
    const journal = { v: 1, t: { messages: { u: { a: { id: 'a', body: 'x'.repeat(16000) } }, d: [] } } }
    const encoded = deflateRawSync(Buffer.from(JSON.stringify(journal)), { level: 0 }).toString('base64url')
    expect(encoded.length).toBeGreaterThan(CHUNK_SIZE * DEMO_STATE_MAX_CHUNKS)
    expect(decodeJournal(encoded)).toEqual(emptyJournal())
  })
})
