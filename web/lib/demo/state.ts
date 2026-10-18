import 'server-only'
import { cookies } from 'next/headers'
import { DEMO_COOKIE, DEMO_STATE_COOKIE, DEMO_STATE_MAX_CHUNKS, parseDemoStart } from './constants'
import { createDemoClient, type DemoClient, type DemoDatabase } from './emulator'
import { applyJournal, chunk, decodeJournal, encodeJournal, recordChange, type DemoJournal } from './journal'
import { buildDemoTables } from './seed'

type CookieStore = Awaited<ReturnType<typeof cookies>>

type DemoSession = { client: DemoClient; db: DemoDatabase; journal: DemoJournal }

// One demo database per request (keyed on that request's cookie store), so a
// server action's writes are visible to the reads that follow it.
const sessions = new WeakMap<CookieStore, DemoSession>()

function readJournal(store: CookieStore): DemoJournal {
  let encoded = ''
  for (let i = 0; i < DEMO_STATE_MAX_CHUNKS; i++) {
    const part = store.get(`${DEMO_STATE_COOKIE}.${i}`)?.value
    if (!part) break
    encoded += part
  }
  return decodeJournal(encoded)
}

const cookieOptions = { path: '/', sameSite: 'lax' as const, httpOnly: true, maxAge: 60 * 60 * 24 * 7 }

function writeJournal(store: CookieStore, journal: DemoJournal) {
  const parts = chunk(encodeJournal(journal))
  if (parts.length > DEMO_STATE_MAX_CHUNKS) {
    // The demo has outgrown its cookie budget; keep the last state that fit.
    console.warn('[demo] change journal is full; further demo changes are not persisted')
    return
  }
  try {
    for (let i = 0; i < DEMO_STATE_MAX_CHUNKS; i++) {
      if (i < parts.length) store.set(`${DEMO_STATE_COOKIE}.${i}`, parts[i], cookieOptions)
      else if (store.has(`${DEMO_STATE_COOKIE}.${i}`)) store.delete(`${DEMO_STATE_COOKIE}.${i}`)
    }
  } catch {
    // Server Component render: cookies are read-only there. Writes only happen
    // in server actions, where this succeeds.
  }
}

/** Demo start time when this request is in demo mode, otherwise null. */
export async function getDemoStart(): Promise<number | null> {
  const store = await cookies()
  return parseDemoStart(store.get(DEMO_COOKIE)?.value)
}

export async function isDemoRequest(): Promise<boolean> {
  return (await getDemoStart()) !== null
}

/** The in-memory demo client for this request, or null outside demo mode. */
export async function getDemoClient(): Promise<DemoClient | null> {
  const store = await cookies()
  const start = parseDemoStart(store.get(DEMO_COOKIE)?.value)
  if (start === null) return null
  const existing = sessions.get(store)
  if (existing) return existing.client

  const journal = readJournal(store)
  const db: DemoDatabase = {
    tables: applyJournal(buildDemoTables(start), journal),
    now: () => Date.now(),
    onChange: change => {
      recordChange(journal, change)
      writeJournal(store, journal)
    },
  }
  const session = { client: createDemoClient(db), db, journal }
  sessions.set(store, session)
  return session.client
}

/** Starts (or restarts) demo mode with a fresh seed. Server actions only. */
export async function startDemo(now = Date.now()) {
  const store = await cookies()
  clearDemoState(store)
  store.set(DEMO_COOKIE, String(now), { ...cookieOptions, httpOnly: false })
}

/** Leaves demo mode and forgets every demo change. Server actions only. */
export async function endDemo() {
  const store = await cookies()
  clearDemoState(store)
  if (store.has(DEMO_COOKIE)) store.delete(DEMO_COOKIE)
}

function clearDemoState(store: CookieStore) {
  sessions.delete(store)
  for (let i = 0; i < DEMO_STATE_MAX_CHUNKS; i++) {
    if (store.has(`${DEMO_STATE_COOKIE}.${i}`)) store.delete(`${DEMO_STATE_COOKIE}.${i}`)
  }
}
