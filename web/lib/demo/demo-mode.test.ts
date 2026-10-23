import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// ── Mocked network boundary ────────────────────────────────────────────────
// Every way the web app can reach Supabase is replaced with a spy that fails
// the test if it is ever used while in demo mode.
const { createServerClient, createBrowserClient, createSupabaseClient, cookieJar } = vi.hoisted(() => {
  const jar = new Map<string, string>()
  const realClient = { auth: { getUser: async () => ({ data: { user: null }, error: null }) }, __real: true }
  return {
    cookieJar: jar,
    createServerClient: vi.fn(() => realClient),
    createBrowserClient: vi.fn(() => realClient),
    createSupabaseClient: vi.fn(() => realClient),
  }
})

vi.mock('server-only', () => ({}))
vi.mock('next/cache', () => ({ revalidatePath: vi.fn(), revalidateTag: vi.fn() }))
vi.mock('next/navigation', () => ({
  notFound: () => { throw new Error('NEXT_NOT_FOUND') },
  redirect: (url: string) => { throw new Error(`NEXT_REDIRECT ${url}`) },
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn(), replace: vi.fn() }),
  usePathname: () => '/',
}))
vi.mock('@supabase/ssr', () => ({ createServerClient, createBrowserClient }))
vi.mock('@supabase/supabase-js', () => ({ createClient: createSupabaseClient }))
vi.mock('next/headers', () => {
  const store = {
    get: (name: string) => (cookieJar.has(name) ? { name, value: cookieJar.get(name)! } : undefined),
    getAll: () => [...cookieJar.entries()].map(([name, value]) => ({ name, value })),
    has: (name: string) => cookieJar.has(name),
    set: (name: string, value: string) => { cookieJar.set(name, value) },
    delete: (name: string) => { cookieJar.delete(name) },
  }
  // A fresh store object per call: every createClient() rebuilds the demo
  // database from the seed + cookie journal, like a new request would.
  return { cookies: async () => ({ ...store }), headers: async () => new Headers() }
})

import { DEMO_STATE_COOKIE, DEMO_COOKIE, DEMO_EMAIL, DEMO_USER_ID, isDemoEmail } from './constants'
import { buildDemoTables, demoId, DEMO_KIND, STUDY_SPACE_CLASS_ID } from './seed'
import { decodeJournal, encodeJournal, chunk } from './journal'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { enterDemoMode, exitDemoMode, resetDemoMode } from '@/app/actions/demo'
import { markAttendance, signInKioskStudent, clearAttendance } from '@/app/actions/mobile'
import { getMobileClasses, getMobileProfile, getMobileSession, getMobileSignInEntries } from '@/lib/mobile-queries'
import { getTodayRoster, getTodaySessions } from '@/lib/queries/attendance'
import { getAllStudents, getStudent, getStudentYearHistory } from '@/lib/queries/students'
import { getAttendanceSummary, getDailyAttendance, getMonthlyAttendanceDrops, getWeeklyAttendanceTrend } from '@/lib/queries/analytics'
import { getAuditLog, getRecentEvents } from '@/lib/queries/activity'
import { getAwardCandidates } from '@/lib/queries/awards'
import { getStudentNfcBinding } from '@/lib/queries/nfc'
import { getPendingCorrections, getPrivacyNotice, getStudentConsent } from '@/lib/queries/pdpa'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { pairNfcChip } from '@/app/actions/nfc'
import { todayInTz } from '@/lib/date'
import AdminStudentPage from '@/app/(admin)/students/[id]/page'
import MobileStudentPage from '@/app/mobile/students/[id]/page'
import { isValidElement, type ReactNode } from 'react'

const fetchSpy = vi.fn(async () => {
  throw new Error('Network access is not allowed in demo mode')
})

beforeEach(() => {
  cookieJar.clear()
  vi.clearAllMocks()
  vi.stubGlobal('fetch', fetchSpy)
})

afterEach(() => {
  vi.unstubAllGlobals()
})

function expectNoSupabase() {
  expect(createServerClient).not.toHaveBeenCalled()
  expect(createBrowserClient).not.toHaveBeenCalled()
  expect(createSupabaseClient).not.toHaveBeenCalled()
  expect(fetchSpy).not.toHaveBeenCalled()
}

const NICK = demoId(DEMO_KIND.student, 1)
const FAMILIAR_NAMES = ['Lauren Tan', 'Brian Chew', 'Agrim Singh', 'Nick Chan']
const LAUREN = demoId(DEMO_KIND.student, 7)

describe('demo email', () => {
  it('matches only the demo address, case-insensitively', () => {
    expect(DEMO_EMAIL).toBe('demo@thegoodcompanysg.dev')
    expect(isDemoEmail('demo@thegoodcompanysg.dev')).toBe(true)
    expect(isDemoEmail('  Demo@TheGoodCompanySG.dev ')).toBe(true)
    expect(isDemoEmail('edmund@thegoodcompanysg.dev')).toBe(false)
    expect(isDemoEmail('demo@thegoodcompanysg.dev.evil.com')).toBe(false)
    expect(isDemoEmail('')).toBe(false)
  })

  it('signing in with the demo email turns on demo mode without touching Supabase', async () => {
    expect(await enterDemoMode('DEMO@thegoodcompanysg.dev')).toEqual({ error: null })
    expect(cookieJar.get(DEMO_COOKIE)).toMatch(/^\d+$/)
    const client = await createClient()
    expect((client as unknown as { __demo?: boolean }).__demo).toBe(true)
    const { data } = await client.auth.getUser()
    expect(data.user?.id).toBe(DEMO_USER_ID)
    expectNoSupabase()
  })

  it('refuses to start demo mode for any other email', async () => {
    expect((await enterDemoMode('edmund@thegoodcompanysg.dev')).error).toBeTruthy()
    expect(cookieJar.has(DEMO_COOKIE)).toBe(false)
  })
})

describe('demo seed', () => {
  const tables = buildDemoTables(Date.parse('2026-10-19T09:00:00+08:00'))

  it('covers every screen with invented data', () => {
    expect(tables.classes.filter(c => !c.is_study_space)).toHaveLength(4)
    expect(tables.classes.some(c => c.id === STUDY_SPACE_CLASS_ID && c.is_study_space)).toBe(true)
    expect(tables.students).toHaveLength(24)
    for (const t of ['enrollments', 'sessions', 'attendance_records', 'student_results', 'result_slips', 'messages', 'parent_student_links', 'awards', 'correction_requests', 'consent_records', 'policy_documents', 'feature_flags', 'class_tutor_assignments']) {
      expect(tables[t]?.length, t).toBeGreaterThan(0)
    }
    expect(tables.sessions.filter(s => s.session_date === '2026-10-19')).toHaveLength(4)
  })

  it('includes the familiar names as ordinary students with ids identical to iOS', () => {
    for (const name of FAMILIAR_NAMES) {
      expect(tables.students.some(s => s.full_name === name), name).toBe(true)
    }
    expect(tables.students.find(s => s.id === 'de000003-0000-4000-8000-000000000001')?.full_name).toBe('Nick Chan')
  })

  it('gives Lauren Tan a full-attendance record', () => {
    const lauren = tables.attendance_records.filter(r => r.student_id === LAUREN)
    expect(lauren.length).toBeGreaterThan(0)
    expect(lauren.every(r => r.status === 'present')).toBe(true)
  })

  it('contains no NRIC-like strings', () => {
    expect(JSON.stringify(tables)).not.toMatch(/\b[STFGM][0-9]{7}[A-Z]\b/)
  })
})

describe('demo mode reads and writes never reach Supabase', () => {
  beforeEach(async () => {
    await enterDemoMode(DEMO_EMAIL)
    vi.clearAllMocks()
  })

  it('serves dashboard, analytics, student, PDPA and mobile reads from the demo store', async () => {
    expect((await getMobileProfile())?.role).toBe('admin')
    expect(await getMobileClasses()).toHaveLength(4)
    expect((await getAllStudents()).length).toBe(24)
    expect((await getStudent(NICK))?.full_name).toBe('Nick Chan')
    expect((await getStudentYearHistory(LAUREN)).length).toBeGreaterThan(0)
    expect((await getTodaySessions()).length).toBe(4)
    expect((await getTodayRoster()).length).toBe(24)
    expect((await getAttendanceSummary()).length).toBeGreaterThan(0)
    await getDailyAttendance()
    await getWeeklyAttendanceTrend()
    await getMonthlyAttendanceDrops()
    await getAuditLog({})
    await getRecentEvents({})
    await getAwardCandidates()
    expect(await getStudentNfcBinding(LAUREN)).toMatchObject({ chipUidSuffix: '7A2F' })
    expect(await getPrivacyNotice()).not.toBeNull()
    expect((await getStudentConsent(NICK)).length).toBeGreaterThan(0)
    expect((await getPendingCorrections()).length).toBe(1)
    expect(await isFeatureEnabled('nfc_sign_in')).toBe(true)
    expect((await getMobileSignInEntries()).length).toBe(24)
    expectNoSupabase()
  })

  it('records check-ins only in this browser and keeps them across requests', async () => {
    const today = todayInTz()
    const session = (await (await createClient()).from('sessions').select('id, class_id').eq('session_date', today).eq('class_id', demoId(DEMO_KIND.class, 1)).single()).data
    expect(session).toBeTruthy()

    expect(await markAttendance(session!.id, NICK, 'present')).toEqual({ error: null })
    expect(cookieJar.get('tava_demo_state.0')).toBeTruthy()

    // A later request rebuilds the store from the seed + this browser's journal.
    const roster = (await getMobileSession(session!.id))!.roster
    expect(roster.find(r => r.studentId === NICK)?.status).toBe('present')

    expect(await clearAttendance(session!.id, NICK)).toEqual({ error: null })
    expect((await getMobileSession(session!.id))!.roster.find(r => r.studentId === NICK)?.status).toBeNull()

    const kiosk = await getMobileSignInEntries()
    const nick = kiosk.find(e => e.studentId === NICK)!
    expect((await signInKioskStudent(nick.sessionIds, NICK)).error).toBeNull()

    expect((await pairNfcChip(NICK, '04A1B2C3D4E5F6')).suffix).toBe('E5F6')
    expect(await getStudentNfcBinding(NICK)).toMatchObject({ chipUidSuffix: 'E5F6' })

    // The admin (service-role) client is the demo store too.
    const admin = await createAdminClient()
    expect((admin as unknown as { __demo?: boolean }).__demo).toBe(true)
    expectNoSupabase()
  })

  it('reset throws away demo changes; signing out leaves demo mode', async () => {
    const session = (await (await createClient()).from('sessions').select('id').eq('session_date', todayInTz()).eq('class_id', demoId(DEMO_KIND.class, 1)).single()).data!
    await markAttendance(session.id, NICK, 'late')
    expect(cookieJar.has('tava_demo_state.0')).toBe(true)

    expect(await resetDemoMode()).toEqual({ error: null })
    expect(cookieJar.has('tava_demo_state.0')).toBe(false)
    expect((await getMobileSession(session.id))!.roster.find(r => r.studentId === NICK)?.status).toBeNull()

    await exitDemoMode()
    expect(cookieJar.has(DEMO_COOKIE)).toBe(false)
    expectNoSupabase()
  })

  it('refuses destructive admin operations in demo mode', async () => {
    const client = await createClient()
    const { error } = await client.rpc('wipe_operational_data_secure', { confirmation: 'x' })
    expect(error).toBeTruthy()
    expect((await client.rpc('is_superadmin')).data).toBe(false)
    expectNoSupabase()
  })

  it('keeps a full evening of check-ins within the cookie budget', async () => {
    const client = await createClient()
    const { data: sessions } = await client.from('sessions').select('id').eq('session_date', todayInTz())
    for (const s of sessions ?? []) {
      const { data: roster } = await client.rpc('get_session_roster', { p_session_id: s.id })
      for (const row of roster ?? []) await markAttendance(s.id, row.student_id, 'present')
    }
    const encoded = [0, 1, 2, 3].map(i => cookieJar.get(`tava_demo_state.${i}`) ?? '').join('')
    expect(encoded.length).toBeGreaterThan(0)
    expect(chunk(encoded).length).toBeLessThanOrEqual(4)
    expect(decodeJournal(encoded).t.attendance_records).toBeTruthy()
    expect((await getTodayRoster()).every(r => r.status === 'present')).toBe(true)
    expectNoSupabase()
  })
})

describe('non-demo sign-in', () => {
  it('uses the real Supabase clients when the demo cookie is absent', async () => {
    const client = await createClient()
    expect((client as unknown as { __real?: boolean }).__real).toBe(true)
    expect(createServerClient).toHaveBeenCalledTimes(1)
    await createAdminClient()
    expect(createSupabaseClient).toHaveBeenCalledTimes(1)
  })

  it('ignores a malformed demo cookie', async () => {
    cookieJar.set(DEMO_COOKIE, 'yes please')
    await createClient()
    expect(createServerClient).toHaveBeenCalledTimes(1)
  })
})

describe('journal encoding', () => {
  it('round-trips and tolerates corruption', () => {
    const journal = { v: 1 as const, t: { messages: { u: { a: { id: 'a', body: 'hi' } }, d: ['b'] } } }
    expect(decodeJournal(encodeJournal(journal))).toEqual(journal)
    expect(decodeJournal('not-valid')).toEqual({ v: 1, t: {} })
  })
})

/** Every literal string, string prop and component name in a rendered element tree. */
function collectUi(node: ReactNode, out: string[] = []): string[] {
  if (node === null || node === undefined || typeof node === 'boolean') return out
  if (typeof node === 'string' || typeof node === 'number') { out.push(String(node)); return out }
  if (Array.isArray(node)) { node.forEach(child => collectUi(child, out)); return out }
  if (isValidElement(node)) {
    const type = node.type as unknown
    const typeName = typeof type === 'string' ? type
      : typeof type === 'function' ? (type as { name?: string }).name
      : (type as { displayName?: string; render?: { name?: string } } | null)?.displayName ?? (type as { render?: { name?: string } } | null)?.render?.name
    out.push(`<${typeName || 'anonymous'}>`)
    for (const [key, value] of Object.entries((node.props ?? {}) as Record<string, unknown>)) {
      if (key === 'children') collectUi(value as ReactNode, out)
      else if (typeof value === 'string') out.push(value)
      else if (isValidElement(value) || Array.isArray(value)) collectUi(value as ReactNode, out)
    }
  }
  return out
}

describe('familiar names are the only Easter egg', () => {
  beforeEach(async () => {
    await enterDemoMode(DEMO_EMAIL)
    vi.clearAllMocks()
  })

  it('renders their student profiles exactly like any other student (no Easter-egg UI)', async () => {
    const client = await createClient()
    const { data: students } = await client.from('students').select('id, full_name')
    const ordinary = students!.find(s => s.full_name === 'Ryan Teo')!
    const shape = (ui: string[]) => ui.filter(t => t.startsWith('<')).filter((t, i, all) => all.indexOf(t) === i).sort()

    for (const Page of [AdminStudentPage, MobileStudentPage]) {
      const baseline = collectUi(await Page({ params: Promise.resolve({ id: ordinary.id }) }))
      expect(shape(baseline).length).toBeGreaterThan(2)
      for (const name of FAMILIAR_NAMES) {
        const student = students!.find(s => s.full_name === name)!
        const ui = collectUi(await Page({ params: Promise.resolve({ id: student.id }) }))
        const text = ui.join(' ')
        expect(text).toContain(name)
        expect(text).not.toMatch(/fun fact|🌟|🏀|🚀|🎉|easter|confetti/i)
        expect(ui.some(t => /^<Demo/.test(t)), `${name} profile has no demo-only component`).toBe(false)
        // Same components as an ordinary student's profile.
        expect(shape(ui)).toEqual(shape(baseline))
      }
    }

    // Checking them in has no side effect beyond the attendance write.
    const { data: sessions } = await client.from('sessions').select('id, class_id').eq('session_date', todayInTz())
    for (const name of FAMILIAR_NAMES) {
      const student = students!.find(s => s.full_name === name)!
      const { data: enrollment } = await client.from('enrollments').select('class_id').eq('student_id', student.id).single()
      const session = sessions!.find(s => s.class_id === enrollment!.class_id)!
      expect(await markAttendance(session.id, student.id, 'present')).toEqual({ error: null })
    }
    expectNoSupabase()
  })
})


describe('untrusted demo journal dashboard', () => {
  it('discards same-day session/enrollment amplification before running the dashboard query', async () => {
    await enterDemoMode(DEMO_EMAIL)
    const baseline = await getTodaySessions()
    const seed = buildDemoTables(Number(cookieJar.get(DEMO_COOKIE)))
    const session = seed.sessions.find(row => row.session_date === todayInTz())!
    const enrollment = seed.enrollments.find(row => row.class_id === session.class_id)!
    const journal = { v: 1 as const, t: {
      sessions: { u: Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`s${i}`, { ...session, id: `s${i}` }])), d: [] },
      enrollments: { u: Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`e${i}`, { ...enrollment, id: `e${i}` }])), d: [] },
    } }
    chunk(encodeJournal(journal)).forEach((part, i) => cookieJar.set(`${DEMO_STATE_COOKIE}.${i}`, part))
    expect(await getTodaySessions()).toEqual(baseline)
    expectNoSupabase()
  })
})
