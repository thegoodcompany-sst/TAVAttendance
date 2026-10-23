import { randomBytes } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { createDemoClient, type DemoDatabase } from './emulator'
import { applyJournal, decodeJournal, emptyJournal, encodeJournal, recordChange } from './journal'
import { buildDemoTables, type DemoTables } from './seed'

function setup(tables: DemoTables = buildDemoTables(Date.UTC(2026, 9, 22))) {
  const journal = emptyJournal()
  const db: DemoDatabase = { tables, now: () => 0, journal,
    onChange: change => recordChange(journal, change) }
  return { db, journal, client: createDemoClient(db) }
}

describe('demo mutation persistence', () => {
  it('accepts the string boundary and preserves it after rejected insert, update, upsert and RPC writes', async () => {
    const { db, journal, client } = setup()
    expect((await client.from('messages').insert({ id: 'saved', body: 'a'.repeat(4096) })).error).toBeNull()
    const before = structuredClone(db.tables)
    const encoded = encodeJournal(journal)
    const oversized = 'b'.repeat(4097)
    for (const result of [
      await client.from('messages').insert([{ body: 'valid' }, { body: oversized }]),
      await client.from('messages').update({ body: oversized }).eq('id', 'saved'),
      await client.from('messages').upsert({ id: 'saved', body: oversized }),
      await client.rpc('send_parent_message', { p_student_id: 'student', p_body: oversized }),
      await client.auth.admin.inviteUserByEmail('demo@example.test', { data: { full_name: oversized } }),
    ]) {
      expect(result.error?.message).toContain('Demo persistence limit')
    }
    expect(db.tables).toEqual(before)
    expect(encodeJournal(journal)).toBe(encoded)
    expect(applyJournal(buildDemoTables(Date.UTC(2026, 9, 22)), decodeJournal(encoded))).toEqual(before)
    expect((await client.from('messages').update({ body: 'still works' }).eq('id', 'saved')).error).toBeNull()
  })

  it('rolls back every table in a multi-table RPC when one row is invalid', async () => {
    const { db, journal, client } = setup()
    const before = structuredClone(db.tables)
    const result = await client.rpc('create_student_with_consent', {
      p_full_name: 'Demo student', p_source_note: 'x'.repeat(4097),
    })
    expect(result.error?.message).toContain('Demo persistence limit')
    expect(db.tables).toEqual(before)
    expect(journal).toEqual(emptyJournal())
  })

  it('counts untouched seed rows against the table limit', async () => {
    const { db, journal, client } = setup({ messages: Array.from({ length: 255 }, (_, i) => ({ id: `m${i}`, body: 'seed' })) })
    expect((await client.from('messages').insert({ id: 'last', body: 'saved' })).error).toBeNull()
    const encoded = encodeJournal(journal)
    expect((await client.from('messages').insert({ body: 'overflow' })).error?.message).toContain('Demo persistence limit')
    expect(db.tables.messages).toHaveLength(256)
    expect(encodeJournal(journal)).toBe(encoded)
  })

  it('counts persisted deletions across requests before accepting another deletion', async () => {
    const { db, journal } = setup({ messages: [{ id: 'remaining', body: 'saved' }] })
    journal.t.messages = { u: {}, d: Array.from({ length: 256 }, (_, i) => `deleted${i}`) }
    const encoded = encodeJournal(journal)
    const result = await createDemoClient(db).from('messages').delete().eq('id', 'remaining')
    expect(result.error?.message).toContain('Demo persistence limit')
    expect(db.tables.messages).toHaveLength(1)
    expect(encodeJournal(journal)).toBe(encoded)
  })

  it('enforces the total merged row limit', async () => {
    const tables = Object.fromEntries(['messages', 'students', 'awards', 'profiles'].map(table => [
      table, Array.from({ length: 256 }, (_, i) => ({ id: `${table}${i}` })),
    ]))
    const { db, client } = setup(tables)
    expect((await client.from('classes').insert({ name: 'overflow' })).error?.message).toContain('Demo persistence limit')
    expect(db.tables).toEqual(tables)
  })

  it('enforces the total journal limit including deletions', async () => {
    const { db, journal, client } = setup({})
    for (const table of ['messages', 'students', 'awards', 'profiles']) {
      journal.t[table] = { u: {}, d: Array.from({ length: 256 }, (_, i) => `deleted${i}`) }
    }
    const encoded = encodeJournal(journal)
    expect((await client.from('classes').insert({ name: 'overflow' })).error?.message).toContain('Demo persistence limit')
    expect(db.tables).toEqual({})
    expect(encodeJournal(journal)).toBe(encoded)
  })

  it.each(['encoded', 'decoded'])('rejects the %s size limit before publishing any changes', async limit => {
    const { db, journal, client } = setup({})
    expect((await client.from('students').insert({ full_name: 'Saved' })).error).toBeNull()
    const before = structuredClone(db.tables)
    const encoded = encodeJournal(journal)
    const rows = Array.from({ length: limit === 'encoded' ? 10 : 256 }, () => ({
      body: limit === 'encoded' ? randomBytes(3000).toString('base64') : 'a'.repeat(4096),
    }))
    expect((await client.from('messages').insert(rows)).error?.message).toContain('Demo persistence limit')
    expect(db.tables).toEqual(before)
    expect(encodeJournal(journal)).toBe(encoded)
  })
})
