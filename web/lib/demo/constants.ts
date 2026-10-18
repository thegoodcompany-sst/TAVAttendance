/**
 * On-device demo mode (web). Signing in as DEMO_EMAIL never talks to Supabase:
 * every server query is answered by an in-memory emulator seeded with invented
 * data, and demo changes live only in this browser's cookies. Mirrors
 * iOS/TAVAttendance/Demo/DemoMode.swift.
 */
export const DEMO_EMAIL = 'demo@thegoodcompanysg.dev'

/** Marks the browser as being in demo mode. Value = demo start time (epoch ms). */
export const DEMO_COOKIE = 'tava_demo'

/** Prefix for the compressed, chunked journal of demo changes. */
export const DEMO_STATE_COOKIE = 'tava_demo_state'

/** Upper bound on journal chunks (each a cookie of at most ~3.8 KB). */
export const DEMO_STATE_MAX_CHUNKS = 4

export const DEMO_USER_ID = 'de000001-0000-4000-8000-000000000001'

export function isDemoEmail(email: string | null | undefined): boolean {
  return (email ?? '').trim().toLowerCase() === DEMO_EMAIL
}

/** Parses the demo cookie value; null when absent or malformed. */
export function parseDemoStart(value: string | null | undefined): number | null {
  if (!value || !/^\d{10,16}$/.test(value)) return null
  const n = Number(value)
  return Number.isFinite(n) && n > 0 ? n : null
}

/** Flags turned on in the demo so every screen has something to show. */
export const DEMO_FEATURE_FLAGS: Record<string, boolean> = {
  parent_portal: true,
  study_space_tracking: true,
  test_mode: true,
  session_notes: true,
  qr_sign_in: true,
  awards: true,
  retrospective_sessions: true,
  nfc_sign_in: true,
  push_notifications: false,
  student_photos: false,
  analytics: false,
}
