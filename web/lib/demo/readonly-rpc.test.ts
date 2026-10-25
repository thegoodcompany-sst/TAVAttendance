import { describe, expect, it, vi } from 'vitest'
import { createDemoClient, type DemoDatabase } from './emulator'
import { emptyJournal } from './journal'

const reads = [
  'get_my_classes', 'get_session_roster', 'get_retrospective_session_roster',
  'get_study_space_roster', 'get_roster_for_date', 'export_student_personal_data',
  'get_student_nfc_binding', 'class_punctuality', 'get_parent_children',
  'get_parent_messages', 'get_parent_result_slips', 'get_parent_attendance_summary',
  'get_parent_attendance_history', 'get_parent_dismissals', 'is_superadmin',
]

describe('demo read-only RPCs', () => {
  it.each(reads)('%s leaves unrelated tables and persistence untouched', async fn => {
    const onChange = vi.fn()
    const unrelatedRead = vi.fn(() => [])
    const db: DemoDatabase = {
      now: () => 0, journal: emptyJournal(), onChange,
      tables: {
        students: [{ id: 'student', full_name: 'Demo student', is_active: true }],
        classes: [{ id: 'class', name: 'Demo class', is_active: true }],
        sessions: [{ id: 'session', class_id: 'class', session_date: '2026-10-22' }],
        enrollments: [{ id: 'enrollment', class_id: 'class', student_id: 'student', is_active: true }],
        get awards() { return unrelatedRead() },
      },
    }
    const tables = db.tables
    const journal = db.journal
    const before = structuredClone(tables)
    unrelatedRead.mockClear()
    const result = await createDemoClient(db).rpc(fn, {
      p_student_id: 'student', p_session_id: 'session', session_id: 'session',
      p_class_id: 'class', p_date: '2026-10-22', p_from: '2026-01-01', p_to: '2026-12-31',
    })
    expect(result.error).toBeNull()
    expect(unrelatedRead).not.toHaveBeenCalled()
    expect(db.tables).toBe(tables)
    expect(db.tables).toEqual(before)
    expect(db.journal).toBe(journal)
    expect(db.journal).toEqual(emptyJournal())
    expect(db.onChange).toBe(onChange)
    expect(onChange).not.toHaveBeenCalled()
  })

  it('returns detached rows without exposing stored data to caller mutations', async () => {
    const db: DemoDatabase = { now: () => 0, tables: {
      students: [{ id: 'student', full_name: 'Demo student' }],
      messages: [{ id: 'message', student_id: 'student', body: 'Original message' }],
      result_slips: [{ id: 'slip', student_id: 'student', exam_name: 'Original exam' }],
    } }
    const before = structuredClone(db.tables)
    const client = createDemoClient(db)
    const exported = await client.rpc('export_student_personal_data', { p_student_id: 'student' })
    exported.data.student.full_name = 'Changed'
    const messages = await client.rpc('get_parent_messages', { p_student_id: 'student' })
    messages.data[0].body = 'Changed'
    const slips = await client.rpc('get_parent_result_slips', { p_student_id: 'student' })
    slips.data[0].exam_name = 'Changed'
    expect(db.tables).toEqual(before)
  })

  it('keeps get-or-create RPCs transactional even though their names start with get', async () => {
    const onChange = vi.fn()
    const db: DemoDatabase = { now: () => 0, journal: emptyJournal(), onChange, tables: {
      classes: [{ id: 'class' }],
      sessions: Array.from({ length: 256 }, (_, i) => ({ id: `s${i}` })),
    } }
    const before = structuredClone(db.tables)
    const result = await createDemoClient(db).rpc('get_or_create_today_session', { p_class_id: 'class' })
    expect(result.error?.message).toContain('Demo persistence limit')
    expect(db.tables).toEqual(before)
    expect(db.journal).toEqual(emptyJournal())
    expect(onChange).not.toHaveBeenCalled()
  })
})
