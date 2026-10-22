/**
 * Demo changes are stored as a per-table journal (rows upserted by id, ids
 * deleted) on top of the deterministic seed, compressed into a few cookies.
 * Nothing about a demo session is stored on the server.
 */
import { deflateRawSync, inflateRawSync } from 'node:zlib'
import { DEMO_STATE_MAX_CHUNKS } from './constants'
import type { DemoChange } from './emulator'
import type { DemoRow, DemoTables } from './seed'

export type DemoJournal = {
  v: 1
  t: Record<string, { u: Record<string, DemoRow>; d: string[] }>
}

export const emptyJournal = (): DemoJournal => ({ v: 1, t: {} })

export function recordChange(journal: DemoJournal, change: DemoChange): void {
  const entry = (journal.t[change.table] ??= { u: {}, d: [] })
  for (const row of change.upserted) {
    entry.u[row.id] = { ...row }
    entry.d = entry.d.filter(id => id !== row.id)
  }
  for (const id of change.deleted) {
    delete entry.u[id]
    if (!entry.d.includes(id)) entry.d.push(id)
  }
}

export function applyJournal(tables: DemoTables, journal: DemoJournal): DemoTables {
  for (const [table, entry] of Object.entries(journal.t)) {
    const deleted = new Set(entry.d)
    const rows = (tables[table] ?? []).filter(row => !deleted.has(row.id))
    const index = new Map(rows.map((row, i) => [row.id, i]))
    for (const row of Object.values(entry.u)) {
      const at = index.get(row.id)
      if (at === undefined) {
        index.set(row.id, rows.length)
        rows.push({ ...row })
      } else {
        rows[at] = { ...rows[at], ...row }
      }
    }
    tables[table] = rows
  }
  return tables
}

/** Max characters per cookie value (browsers allow ~4096 bytes per cookie incl. name). */
export const CHUNK_SIZE = 3800
const MAX_ENCODED_LENGTH = CHUNK_SIZE * DEMO_STATE_MAX_CHUNKS
// Journaling all 398 seeded rows is ~135 KB; allow ample room for demo edits.
const MAX_DECODED_BYTES = 1024 * 1024

export function encodeJournal(journal: DemoJournal): string {
  if (Object.keys(journal.t).length === 0) return ''
  return deflateRawSync(Buffer.from(JSON.stringify(journal), 'utf8'), { level: 9 }).toString('base64url')
}

export function decodeJournal(encoded: string): DemoJournal {
  if (!encoded || encoded.length > MAX_ENCODED_LENGTH) return emptyJournal()
  try {
    const parsed = JSON.parse(inflateRawSync(Buffer.from(encoded, 'base64url'), {
      maxOutputLength: MAX_DECODED_BYTES,
    }).toString('utf8'))
    if (parsed && parsed.v === 1 && typeof parsed.t === 'object') return parsed as DemoJournal
  } catch {
    // A corrupt, truncated or oversized journal falls back to the fresh seed.
  }
  return emptyJournal()
}

export function chunk(encoded: string, size = CHUNK_SIZE): string[] {
  const parts: string[] = []
  for (let i = 0; i < encoded.length; i += size) parts.push(encoded.slice(i, i + size))
  return parts
}
