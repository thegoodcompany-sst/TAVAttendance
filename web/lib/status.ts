export type AttendanceStatus = 'present' | 'late' | 'absent' | null

/** Dashboard/kiosk-facing labels. */
export function statusLabel(status: AttendanceStatus): string {
  if (!status) return 'Not here yet'
  return { present: 'On time', late: 'Late', absent: 'Absent' }[status] ?? status
}

export function statusColor(status: AttendanceStatus): string {
  switch (status) {
    case 'present': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
    case 'late':    return 'bg-amber-50 text-amber-700 border-amber-200'
    case 'absent':  return 'bg-rose-50 text-rose-700 border-rose-200'
    default:        return 'bg-slate-50 text-slate-500 border-slate-200'
  }
}
