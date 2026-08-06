export type AttendanceStatus = 'present' | 'late' | 'absent' | null

/**
 * Dashboard/kiosk-facing labels. Absent is one status with an optional companion
 * flag (`absence_informed`) — never a fourth status value.
 *   TRUE  → "Absent (informed)"
 *   FALSE → "Absent (no notice)"
 *   NULL  → "Absent"
 */
export function statusLabel(
  status: AttendanceStatus,
  absenceInformed: boolean | null = null,
): string {
  if (!status) return 'Not here yet'
  if (status === 'absent') {
    if (absenceInformed === true) return 'Absent (informed)'
    if (absenceInformed === false) return 'Absent (no notice)'
    return 'Absent'
  }
  return { present: 'On time', late: 'Late' }[status] ?? status
}

/** Roster / session-detail wording uses "Present" instead of "On time". */
export function rosterStatusLabel(
  status: AttendanceStatus,
  absenceInformed: boolean | null = null,
): string {
  if (!status) return 'Not here yet'
  if (status === 'present') return 'Present'
  if (status === 'late') return 'Late'
  if (status === 'absent') {
    if (absenceInformed === true) return 'Absent (informed)'
    if (absenceInformed === false) return 'Absent (no notice)'
    return 'Absent'
  }
  return status
}

export function statusColor(status: AttendanceStatus): string {
  switch (status) {
    case 'present': return 'bg-emerald-50 text-emerald-700 border-emerald-200'
    case 'late':    return 'bg-amber-50 text-amber-700 border-amber-200'
    case 'absent':  return 'bg-rose-50 text-rose-700 border-rose-200'
    default:        return 'bg-slate-50 text-slate-500 border-slate-200'
  }
}
