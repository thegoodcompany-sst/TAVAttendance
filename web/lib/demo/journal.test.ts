import { deflateRawSync } from 'node:zlib'
import { describe, expect, it } from 'vitest'
import { DEMO_STATE_MAX_CHUNKS } from './constants'
import { applyJournal, CHUNK_SIZE, decodeJournal, emptyJournal, encodeJournal, recordChange } from './journal'
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

describe('demo journal validation', () => {
  const start = Date.UTC(2026, 9, 22)
  const encode = (value: unknown) => deflateRawSync(Buffer.from(JSON.stringify(value))).toString('base64url')
  const session = buildDemoTables(start).sessions[0]

  it.each([
    { v: 1, t: null },
    { v: 1, t: [] },
    { v: 1, t: { unknown: { u: {}, d: [] } } },
    { v: 1, t: { sessions: { u: [], d: [] } } },
    { v: 1, t: { sessions: { u: {}, d: [null] } } },
    { v: 1, t: { sessions: { u: { x: { ...session, id: 'y' } }, d: [] } } },
    { v: 1, t: { sessions: { u: { x: { id: 'x' } }, d: [] } } },
    { v: 1, t: { sessions: { u: { x: { ...session, id: 'x', class_id: [] } }, d: [] } } },
    { v: 1, t: { sessions: { u: { x: { ...session, id: 'x', session_date: '2026-02-30' } }, d: [] } } },
    { v: 1, t: { students: { u: { x: { id: 'x', is_active: 'true' } }, d: [] } } },
    { v: 1, t: { students: { u: { x: { id: 'x', unexpected: 'field' } }, d: [] } } },
    JSON.parse('{"v":1,"t":{"__proto__":{"u":{},"d":[]}}}'),
    JSON.parse('{"v":1,"t":{"students":{"u":{"__proto__":{"id":"__proto__"}},"d":[]}}}'),
  ])('rejects malformed journal %#', value => {
    expect(decodeJournal(encode(value))).toEqual(emptyJournal())
  })

  it('rejects duplicate session dates and enrollment pairs within the journal', () => {
    for (const [table, row] of [['sessions', session], ['enrollments', buildDemoTables(start).enrollments[0]]] as const) {
      const journal = emptyJournal()
      recordChange(journal, { table, upserted: [{ ...row, id: 'a' }, { ...row, id: 'b' }], deleted: [] })
      expect(decodeJournal(encodeJournal(journal))).toEqual(emptyJournal())
    }
  })

  it.each([300, 900])('rejects the %i-row expansion payload within the byte limits', count => {
    const journal = emptyJournal()
    for (const table of ['sessions', 'enrollments']) {
      const row = table === 'sessions'
        ? { class_id: 'class', session_date: '2026-10-22' }
        : { class_id: 'class', student_id: 'student', is_active: true }
      recordChange(journal, { table, upserted: Array.from({ length: count }, (_, i) => ({ ...row, id: `added-${i}` })), deleted: [] })
    }
    const encoded = encodeJournal(journal)
    expect(encoded.length).toBeLessThan(CHUNK_SIZE * DEMO_STATE_MAX_CHUNKS)
    expect(Buffer.byteLength(JSON.stringify(journal))).toBeLessThan(1024 * 1024)
    expect(decodeJournal(encoded)).toEqual(emptyJournal())
  })

  it('bounds rows even when they have no domain uniqueness key, and bounds deletions', () => {
    const journal = emptyJournal()
    recordChange(journal, { table: 'messages', upserted: Array.from({ length: 257 }, (_, i) => ({ id: `m${i}`, body: 'test' })), deleted: [] })
    expect(decodeJournal(encodeJournal(journal))).toEqual(emptyJournal())
    expect(decodeJournal(encode({ v: 1, t: { messages: { u: {}, d: Array.from({ length: 257 }, (_, i) => `m${i}`) } } }))).toEqual(emptyJournal())
  })

  it('bounds the total across tables', () => {
    const journal = emptyJournal()
    for (const table of ['students', 'messages', 'profiles', 'awards', 'consent_records']) {
      recordChange(journal, { table, upserted: [], deleted: Array.from({ length: 210 }, (_, i) => `removed-${i}`) })
    }
    expect(decodeJournal(encodeJournal(journal))).toEqual(emptyJournal())
  })

  it('rejects seed conflicts atomically but permits replacing a deleted session', () => {
    const tables = buildDemoTables(start)
    const original = structuredClone(tables)
    const journal = emptyJournal()
    recordChange(journal, { table: 'students', upserted: [{ ...tables.students[0], full_name: 'Edited demo' }], deleted: [] })
    recordChange(journal, { table: 'sessions', upserted: [{ ...session, id: 'replacement' }], deleted: [] })
    expect(decodeJournal(encodeJournal(journal))).toEqual(journal)
    expect(applyJournal(tables, journal)).toEqual(original)
    recordChange(journal, { table: 'sessions', upserted: [], deleted: [session.id] })
    const applied = applyJournal(tables, decodeJournal(encodeJournal(journal)))
    expect(applied.sessions.find(row => row.id === 'replacement')).toEqual({ ...session, id: 'replacement' })
    expect(applied.students[0].full_name).toBe('Edited demo')
    expect(tables).toEqual(original)
  })

  it('bounds the merged table, including untouched seeded rows', () => {
    const tables = buildDemoTables(start)
    const journal = emptyJournal()
    recordChange(journal, { table: 'messages', upserted: Array.from({ length: 256 }, (_, i) => ({ id: `new-${i}`, body: 'test' })), deleted: [] })
    expect(decodeJournal(encodeJournal(journal))).toEqual(journal)
    const original = structuredClone(tables)
    expect(applyJournal(tables, journal)).toEqual(original)
    expect(tables).toEqual(original)
  })
})
