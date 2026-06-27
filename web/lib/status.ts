export type AttendanceStatus = 'present' | 'late' | 'absent' | 'excused' | null

export function statusLabel(status: AttendanceStatus): string {
  if (!status) return 'Not here yet'
  return { present: 'Present', late: 'Late', absent: 'Absent', excused: 'Excused' }[status] ?? status
}

export function statusColor(status: AttendanceStatus): string {
  switch (status) {
    case 'present': return 'bg-green-100 text-green-800 border-green-200'
    case 'late':    return 'bg-orange-100 text-orange-800 border-orange-200'
    case 'absent':  return 'bg-red-100 text-red-800 border-red-200'
    case 'excused': return 'bg-gray-100 text-gray-600 border-gray-200'
    default:        return 'bg-gray-50 text-gray-500 border-gray-200'
  }
}
