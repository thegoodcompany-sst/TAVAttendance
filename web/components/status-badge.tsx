import { statusColor, statusLabel, type AttendanceStatus } from '@/lib/status'

export function StatusBadge({ status }: { status: AttendanceStatus }) {
  return (
    <span
      className={`inline-flex items-center whitespace-nowrap rounded-full border px-2.5 py-0.5 text-[0.7rem] font-bold ${statusColor(status)}`}
    >
      {statusLabel(status)}
    </span>
  )
}
