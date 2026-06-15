export function yesterdayInTz(tz = 'Asia/Singapore'): string {
  const d = new Date()
  d.setDate(d.getDate() - 1)
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d)
}

export function todayInTz(tz = 'Asia/Singapore'): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
}

/**
 * Returns the calendar date `offsetDays` days before today in the given
 * timezone, as an ISO date string (YYYY-MM-DD).  Negative values are in
 * the past; 0 is today.  All arithmetic is done in calendar space so the
 * result is never off by a day near midnight regardless of the server's
 * local timezone.
 */
export function dateOffsetInTz(offsetDays: number, tz = 'Asia/Singapore'): string {
  // Derive "today" as a UTC midnight for the calendar date in the target tz.
  const todayStr = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
  // Parse as UTC midnight so Date arithmetic stays in whole days.
  const base = new Date(`${todayStr}T00:00:00Z`)
  base.setUTCDate(base.getUTCDate() + offsetDays)
  return base.toISOString().slice(0, 10)
}

export function formatScheduleTime(raw: string): string {
  const parts = raw.split(':')
  const h = parseInt(parts[0], 10)
  const m = parts[1]
  const ampm = h >= 12 ? 'PM' : 'AM'
  const h12 = h % 12 || 12
  return `${h12}:${m} ${ampm}`
}
