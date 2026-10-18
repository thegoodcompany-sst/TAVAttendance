/**
 * Invented demo dataset. Nothing here is copied from production. Student and
 * class IDs match iOS/TAVAttendance/Demo/DemoSeed.swift so QR codes printed
 * from the web demo scan on the iPad demo kiosk.
 */
import { DEMO_FEATURE_FLAGS, DEMO_USER_ID } from './constants'

export type DemoRow = Record<string, unknown> & { id: string }
export type DemoTables = Record<string, DemoRow[]>

export const DEMO_KIND = {
  profile: 1,
  class: 2,
  student: 3,
  enrollment: 4,
  assignment: 5,
  session: 6,
  attendance: 7,
  result: 8,
  resultSlip: 9,
  message: 10,
  correction: 11,
  dismissal: 12,
  consent: 13,
  link: 14,
  award: 15,
  audit: 16,
  flag: 17,
} as const

export function demoId(kind: number, n: number): string {
  return `de${kind.toString(16).padStart(6, '0')}-0000-4000-8000-${n.toString(16).padStart(12, '0')}`
}

export const STUDY_SPACE_CLASS_ID = '57000000-0000-0000-0000-000000000001'

const TUTOR_RACHEL = demoId(DEMO_KIND.profile, 2)
const TUTOR_DANIEL = demoId(DEMO_KIND.profile, 3)
const TUTOR_PRIYA = demoId(DEMO_KIND.profile, 4)
const PARENT_SITI = demoId(DEMO_KIND.profile, 5)
const PARENT_JASON = demoId(DEMO_KIND.profile, 6)

type ClassSpec = { n: number; name: string; subject: string; level: string; day: string; byday: string; jsWeekday: number; tutors: string[] }

export const DEMO_CLASS_SPECS: readonly ClassSpec[] = [
  { n: 1, name: 'P5 English', subject: 'English', level: 'P5', day: 'Monday', byday: 'MO', jsWeekday: 1, tutors: [TUTOR_RACHEL, TUTOR_PRIYA] },
  { n: 2, name: 'P6 Mathematics', subject: 'Math', level: 'P6', day: 'Thursday', byday: 'TH', jsWeekday: 4, tutors: [TUTOR_DANIEL, TUTOR_PRIYA] },
  { n: 3, name: 'Sec 1 English', subject: 'English', level: 'Sec 1', day: 'Monday', byday: 'MO', jsWeekday: 1, tutors: [TUTOR_RACHEL] },
  { n: 4, name: 'Sec 2 Mathematics', subject: 'Math', level: 'Sec 2', day: 'Thursday', byday: 'TH', jsWeekday: 4, tutors: [TUTOR_DANIEL] },
]

type StudentSpec = { n: number; name: string; school: string; year: string; classN: number }

export const DEMO_STUDENT_SPECS: readonly StudentSpec[] = [
  { n: 1, name: 'Nick Chan', school: 'Bukit View Primary', year: 'P5', classN: 1 },
  { n: 2, name: 'Aisyah Binte Rahim', school: 'Keming Primary', year: 'P5', classN: 1 },
  { n: 3, name: 'Ethan Lim Jun Hao', school: 'Dazhong Primary', year: 'P5', classN: 1 },
  { n: 4, name: 'Kavya Raj', school: 'Bukit View Primary', year: 'P5', classN: 1 },
  { n: 5, name: 'Ryan Teo', school: 'Lianhua Primary', year: 'P5', classN: 1 },
  { n: 6, name: 'Chloe Ng', school: 'Keming Primary', year: 'P5', classN: 1 },
  { n: 7, name: 'Lauren Tan', school: 'Princess Elizabeth Primary', year: 'P6', classN: 2 },
  { n: 8, name: 'Muhammad Irfan', school: 'Dazhong Primary', year: 'P6', classN: 2 },
  { n: 9, name: 'Isabelle Wong', school: 'Bukit View Primary', year: 'P6', classN: 2 },
  { n: 10, name: 'Jayden Goh', school: 'Keming Primary', year: 'P6', classN: 2 },
  { n: 11, name: 'Nurul Huda', school: 'Lianhua Primary', year: 'P6', classN: 2 },
  { n: 12, name: 'Arjun Pillai', school: 'Princess Elizabeth Primary', year: 'P6', classN: 2 },
  { n: 13, name: 'Agrim Singh', school: 'Bukit Batok Secondary', year: 'Sec 1', classN: 3 },
  { n: 14, name: 'Megan Lee', school: 'Hillgrove Secondary', year: 'Sec 1', classN: 3 },
  { n: 15, name: 'Darren Ong', school: 'Bukit Batok Secondary', year: 'Sec 1', classN: 3 },
  { n: 16, name: 'Sophia Chua', school: 'Swiss Cottage Secondary', year: 'Sec 1', classN: 3 },
  { n: 17, name: 'Aaliyah Hassan', school: 'Hillgrove Secondary', year: 'Sec 1', classN: 3 },
  { n: 18, name: 'Caleb Seah', school: 'Bukit Batok Secondary', year: 'Sec 1', classN: 3 },
  { n: 19, name: 'Brian Chew', school: 'Swiss Cottage Secondary', year: 'Sec 2', classN: 4 },
  { n: 20, name: 'Marcus Yeo', school: 'Hillgrove Secondary', year: 'Sec 2', classN: 4 },
  { n: 21, name: 'Tan Hui Min', school: 'Bukit Batok Secondary', year: 'Sec 2', classN: 4 },
  { n: 22, name: 'Zachary Lau', school: 'Swiss Cottage Secondary', year: 'Sec 2', classN: 4 },
  { n: 23, name: 'Natalie Ho', school: 'Hillgrove Secondary', year: 'Sec 2', classN: 4 },
  { n: 24, name: 'Javier Toh', school: 'Bukit Batok Secondary', year: 'Sec 2', classN: 4 },
]

export const DEMO_PAST_WEEKS = 8

const SESSION_NOTES = [
  'Great energy tonight. Dinner was fried bee hoon.',
  'Revision for the upcoming test; most finished the worksheet.',
  'Reading circle went well. Two kids volunteered to read aloud.',
  'Heavy rain, a few arrived late.',
]

const PRIMARY_BANDS = ['AL1', 'AL2', 'AL3', 'AL4', 'AL5', 'AL6', 'AL7', 'AL8']
const SECONDARY_BANDS = ['A1', 'A2', 'B3', 'B4', 'C5', 'C6', 'D7', 'E8', 'F9']

/** Same deterministic pattern as DemoSeed.pastStatus on iOS. */
export function demoPastStatus(studentN: number, sessionIndex: number, name: string): { status: 'present' | 'late' | 'absent'; informed: boolean | null; v: number } {
  const v = (studentN * 37 + sessionIndex * 53 + 11) % 100
  if (name === 'Lauren Tan') return { status: 'present', informed: null, v }
  if (v < 8) return { status: 'absent', informed: v % 2 === 0, v }
  if (v < 18) return { status: 'late', informed: null, v }
  return { status: 'present', informed: null, v }
}

function demoGrade(studentN: number, subject: string, year: string, name: string): string {
  const primary = year.startsWith('P')
  if (name === 'Lauren Tan') return primary ? 'AL1' : 'A1'
  const bands = primary ? PRIMARY_BANDS : SECONDARY_BANDS
  return bands[(studentN * 7 + (subject === 'Math' ? 3 : 1)) % 5]
}

/** YYYY-MM-DD in Asia/Singapore. */
export function sgDate(ms: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(ms))
}

function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + days)
  return d.toISOString().slice(0, 10)
}

function sgTime(date: string, hour: number, minute: number): string {
  return new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00+08:00`).toISOString()
}

/** Builds every demo table for a demo that started at `now` (epoch ms). */
export function buildDemoTables(now: number): DemoTables {
  const today = sgDate(now)
  const iso = (ms: number) => new Date(ms).toISOString()
  const daysAgo = (n: number) => now - n * 86_400_000

  const profiles: DemoRow[] = [
    { id: DEMO_USER_ID, full_name: 'Demo Admin', role: 'admin', phone: null, created_at: iso(daysAgo(200)) },
    { id: TUTOR_RACHEL, full_name: 'Rachel Lim', role: 'tutor', phone: null, created_at: iso(daysAgo(180)) },
    { id: TUTOR_DANIEL, full_name: 'Daniel Koh', role: 'tutor', phone: null, created_at: iso(daysAgo(170)) },
    { id: TUTOR_PRIYA, full_name: 'Priya Nair', role: 'tutor', phone: null, created_at: iso(daysAgo(150)) },
    { id: PARENT_SITI, full_name: 'Siti Rahman', role: 'parent', phone: null, created_at: iso(daysAgo(120)) },
    { id: PARENT_JASON, full_name: 'Jason Goh', role: 'parent', phone: null, created_at: iso(daysAgo(110)) },
  ]

  const classes: DemoRow[] = DEMO_CLASS_SPECS.map(spec => ({
    id: demoId(DEMO_KIND.class, spec.n),
    name: spec.name,
    subject: spec.subject,
    level: spec.level,
    schedule_day: spec.day,
    schedule_time: '19:00:00',
    duration_minutes: 120,
    is_active: true,
    recurrence_rule: `FREQ=WEEKLY;BYDAY=${spec.byday}`,
    recurrence_end_date: null,
    is_study_space: false,
    created_at: iso(daysAgo(200)),
  }))
  classes.push({
    id: STUDY_SPACE_CLASS_ID, name: 'Study Space', subject: null, level: null,
    schedule_day: null, schedule_time: null, duration_minutes: 120, is_active: true,
    recurrence_rule: null, recurrence_end_date: null, is_study_space: true, created_at: iso(daysAgo(200)),
  })

  const students: DemoRow[] = DEMO_STUDENT_SPECS.map(s => ({
    id: demoId(DEMO_KIND.student, s.n),
    full_name: s.name,
    school: s.school,
    year_of_study: s.year,
    is_active: true,
    avatar_url: null,
    notes: null,
    date_of_birth: null,
    created_at: iso(daysAgo(150)),
  }))

  const enrollments: DemoRow[] = DEMO_STUDENT_SPECS.map(s => ({
    id: demoId(DEMO_KIND.enrollment, s.n),
    student_id: demoId(DEMO_KIND.student, s.n),
    class_id: demoId(DEMO_KIND.class, s.classN),
    is_active: true,
    enrolled_at: iso(daysAgo(150)),
    unenrolled_at: null,
  }))

  const assignments: DemoRow[] = []
  for (const spec of DEMO_CLASS_SPECS) {
    for (const tutor of spec.tutors) {
      assignments.push({ id: demoId(DEMO_KIND.assignment, assignments.length + 1), class_id: demoId(DEMO_KIND.class, spec.n), tutor_id: tutor, assigned_until: null })
    }
  }

  const sessions: DemoRow[] = []
  const attendance: DemoRow[] = []
  for (const spec of DEMO_CLASS_SPECS) {
    const classId = demoId(DEMO_KIND.class, spec.n)
    const roster = DEMO_STUDENT_SPECS.filter(s => s.classN === spec.n)
    let latest = addDays(today, -1)
    while (new Date(`${latest}T00:00:00Z`).getUTCDay() !== spec.jsWeekday) latest = addDays(latest, -1)
    for (let week = 0; week < DEMO_PAST_WEEKS; week++) {
      const day = addDays(latest, -7 * week)
      const sessionId = demoId(DEMO_KIND.session, spec.n * 100 + week + 1)
      sessions.push({
        id: sessionId, class_id: classId, session_date: day, topic: null,
        notes: week % 3 === 0 ? SESSION_NOTES[(spec.n + week) % SESSION_NOTES.length] : null,
        started_at: sgTime(day, 19, 0), ended_at: sgTime(day, 21, 0), sub_tutor_id: null,
        created_at: sgTime(day, 18, 30),
      })
      for (const student of roster) {
        const { status, informed, v } = demoPastStatus(student.n, spec.n * 10 + week, student.name)
        const markedAt = status === 'present' ? sgTime(day, 18, 40 + (v % 20))
          : status === 'late' ? sgTime(day, 19, 5 + (v % 25))
            : sgTime(day, 19, 45)
        attendance.push({
          id: demoId(DEMO_KIND.attendance, attendance.length + 1),
          session_id: sessionId,
          student_id: demoId(DEMO_KIND.student, student.n),
          status,
          marked_at: markedAt,
          marked_by: spec.tutors[0],
          notes: null,
          late_reason: status === 'late' ? (v % 2 === 0 ? 'Bus was late' : 'School CCA ran over') : null,
          absence_informed: status === 'absent' ? informed : null,
          client_mutation_id: null,
        })
      }
    }
    sessions.push({
      id: demoId(DEMO_KIND.session, spec.n * 100), class_id: classId, session_date: today, topic: null,
      notes: null, started_at: null, ended_at: null, sub_tutor_id: null, created_at: iso(now),
    })
  }

  for (const [studentN, classN, minutesAgo] of [[2, 1, 25], [3, 1, 18], [14, 3, 12]] as const) {
    attendance.push({
      id: demoId(DEMO_KIND.attendance, attendance.length + 1),
      session_id: demoId(DEMO_KIND.session, classN * 100),
      student_id: demoId(DEMO_KIND.student, studentN),
      status: 'present',
      marked_at: iso(now - minutesAgo * 60_000),
      marked_by: DEMO_USER_ID,
      notes: null,
      late_reason: null,
      absence_informed: null,
      client_mutation_id: null,
    })
  }

  const studentResults: DemoRow[] = []
  for (const s of DEMO_STUDENT_SPECS) {
    for (const subject of ['Math', 'English']) {
      studentResults.push({
        id: demoId(DEMO_KIND.result, studentResults.length + 1),
        student_id: demoId(DEMO_KIND.student, s.n),
        subject,
        grade: demoGrade(s.n, subject, s.year, s.name),
        updated_by: DEMO_USER_ID,
        updated_at: iso(daysAgo(30)),
      })
    }
  }

  const resultSlips: DemoRow[] = [
    { id: demoId(DEMO_KIND.resultSlip, 1), student_id: demoId(DEMO_KIND.student, 7), exam_name: 'SA1 Mathematics', exam_date: sgDate(daysAgo(40)), subject: 'Math', score: 34, max_score: 35, file_path: null, uploaded_by: PARENT_SITI, uploaded_at: iso(daysAgo(38)), acknowledged_at: iso(daysAgo(37)), acknowledged_by: DEMO_USER_ID },
    { id: demoId(DEMO_KIND.resultSlip, 2), student_id: demoId(DEMO_KIND.student, 1), exam_name: 'WA2 English', exam_date: sgDate(daysAgo(20)), subject: 'English', score: 27, max_score: 30, file_path: null, uploaded_by: DEMO_USER_ID, uploaded_at: iso(daysAgo(19)), acknowledged_at: null, acknowledged_by: null },
    { id: demoId(DEMO_KIND.resultSlip, 3), student_id: demoId(DEMO_KIND.student, 19), exam_name: 'Mid-year Mathematics', exam_date: sgDate(daysAgo(60)), subject: 'Math', score: 78, max_score: 100, file_path: null, uploaded_by: DEMO_USER_ID, uploaded_at: iso(daysAgo(58)), acknowledged_at: iso(daysAgo(55)), acknowledged_by: DEMO_USER_ID },
    { id: demoId(DEMO_KIND.resultSlip, 4), student_id: demoId(DEMO_KIND.student, 2), exam_name: 'WA2 English', exam_date: sgDate(daysAgo(21)), subject: 'English', score: 24, max_score: 30, file_path: null, uploaded_by: PARENT_SITI, uploaded_at: iso(daysAgo(18)), acknowledged_at: null, acknowledged_by: null },
  ]

  const messages: DemoRow[] = [
    { id: demoId(DEMO_KIND.message, 1), sender_id: PARENT_SITI, recipient_id: null, student_id: demoId(DEMO_KIND.student, 2), subject: 'Running late on Monday', body: 'Hi teacher, Aisyah will be about 15 minutes late on Monday because of a dentist appointment. Thank you!', sent_at: iso(daysAgo(3)), read_at: iso(daysAgo(2)) },
    { id: demoId(DEMO_KIND.message, 2), sender_id: DEMO_USER_ID, recipient_id: PARENT_SITI, student_id: demoId(DEMO_KIND.student, 2), subject: 'Re: Running late on Monday', body: "Noted, thanks Mdm Siti! We'll save her a seat and keep dinner for her.", sent_at: iso(daysAgo(2)), read_at: iso(daysAgo(2)) },
    { id: demoId(DEMO_KIND.message, 3), sender_id: PARENT_JASON, recipient_id: null, student_id: demoId(DEMO_KIND.student, 10), subject: 'Dinner on Thursday', body: 'Hello! Can Jayden bring his own dinner on Thursday? He is avoiding peanuts for now.', sent_at: iso(daysAgo(1)), read_at: null },
  ]

  const consentRecords: DemoRow[] = DEMO_STUDENT_SPECS.map(s => ({
    id: demoId(DEMO_KIND.consent, s.n),
    student_id: demoId(DEMO_KIND.student, s.n),
    consent_type: 'data_collection',
    status: 'granted',
    method: 'paper_form',
    notice_version: '1.1',
    granted_by: DEMO_USER_ID,
    parent_id: null,
    source_note: 'Demo seed',
    created_at: iso(daysAgo(90)),
  }))

  const corrections: DemoRow[] = [
    { id: demoId(DEMO_KIND.correction, 1), student_id: demoId(DEMO_KIND.student, 5), requested_by: PARENT_JASON, field_name: 'school', current_value: 'Lianhua Primary', requested_value: 'Lianhua Primary School', status: 'pending', reviewed_by: null, reviewed_at: null, review_note: null, created_at: iso(daysAgo(2)) },
  ]

  const parentLinks: DemoRow[] = [
    { id: demoId(DEMO_KIND.link, 1), parent_id: PARENT_SITI, student_id: demoId(DEMO_KIND.student, 2) },
    { id: demoId(DEMO_KIND.link, 2), parent_id: PARENT_JASON, student_id: demoId(DEMO_KIND.student, 10) },
  ]

  const period = today.slice(0, 7)
  const awards: DemoRow[] = [
    { id: demoId(DEMO_KIND.award, 1), student_id: demoId(DEMO_KIND.student, 7), award_type: 'perfect_attendance', period, awarded_at: iso(daysAgo(1)), awarded_by: DEMO_USER_ID },
  ]

  const featureFlags: DemoRow[] = Object.entries(DEMO_FEATURE_FLAGS).map(([key, enabled], i) => ({
    id: demoId(DEMO_KIND.flag, i + 1), key, enabled, description: `Demo flag: ${key.replace(/_/g, ' ')}`, updated_at: iso(daysAgo(10)),
  }))

  const auditLog: DemoRow[] = attendance.slice(-6).map((row, i) => ({
    id: demoId(DEMO_KIND.audit, i + 1),
    table_name: 'attendance_records',
    record_id: row.id,
    action: 'INSERT',
    old_data: null,
    new_data: { student_id: row.student_id, session_id: row.session_id, status: row.status },
    changed_by: row.marked_by,
    changed_at: row.marked_at,
  }))

  return {
    profiles,
    classes,
    students,
    enrollments,
    class_tutor_assignments: assignments,
    sessions,
    attendance_records: attendance,
    student_results: studentResults,
    result_slips: resultSlips,
    result_slip_upload_intents: [],
    messages,
    parent_student_links: parentLinks,
    awards,
    correction_requests: corrections,
    consent_records: consentRecords,
    policy_documents: [{
      id: 'de00000d-0000-4000-8000-000000000001',
      doc_type: 'data_protection_notice',
      version: '1.1',
      title: 'TAVA Attendance — Data Protection Notice (demo)',
      body: 'This is demo mode. Everything you see is invented sample data, and changes stay in this browser only.\n\nIn the real app, TAVA collects each child\'s name, school, level, and attendance so tutors can account for every child, contact parents when needed, and keep the centre safe. Data is kept only as long as it is needed and is never sold or shared for marketing.',
      is_current: true,
      published_at: iso(daysAgo(120)),
    }],
    feature_flags: featureFlags,
    audit_log: auditLog,
    app_events: [],
    dismissals: [],
    nfc_chip_bindings: [{ id: demoId(DEMO_KIND.student, 1001), student_id: demoId(DEMO_KIND.student, 7), chip_uid_suffix: '7A2F', issued_at: iso(daysAgo(14)), revoked_at: null }],
    student_storage_cleanup_queue: [],
  }
}
