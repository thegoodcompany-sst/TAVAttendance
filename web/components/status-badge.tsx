import { statusColor, statusLabel, type AttendanceStatus } from '@/lib/status'

export function StatusBadge({ status }: { status: AttendanceStatus }) {
  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border ${statusColor(status)}`}
    >
      {statusLabel(status)}
    </span>
  )
}
