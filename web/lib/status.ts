export type AttendanceStatus = 'present' | 'late' | 'absent' | 'excused' | null

/** Dashboard/kiosk-facing labels — matches docs/drafts/web-dashboard-ui.html. */
export function statusLabel(status: AttendanceStatus): string {
  if (!status) return 'Unsigned'
  return { present: 'On time', late: 'Late', absent: 'Absent', excused: 'Excused' }[status] ?? status
}

export function statusColor(status: AttendanceStatus): string {
  switch (status) {
    case 'present': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
    case 'late':    return 'bg-amber-50 text-amber-700 border-amber-200'
    case 'absent':  return 'bg-rose-50 text-rose-700 border-rose-200'
    case 'excused': return 'bg-slate-100 text-slate-600 border-slate-200'
    default:        return 'bg-slate-50 text-slate-500 border-slate-200'
  }
}
