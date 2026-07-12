import { notFound } from 'next/navigation'
import QRCode from 'qrcode'
import { PageHeader } from '@/components/dashboard/page-header'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { getAllStudents } from '@/lib/queries'
import { PrintButton } from './print-button'

export const dynamic = 'force-dynamic'

export default async function StudentQrPage() {
  if (!(await isFeatureEnabled('qr_sign_in'))) notFound()

  const students = await getAllStudents()

  // Payload is the raw student UUID, matching the iOS kiosk QR scanner.
  const codes = await Promise.all(
    students.map(async s => ({
      id: s.id,
      fullName: s.fullName,
      svg: await QRCode.toString(s.id, { type: 'svg', margin: 1 }),
    }))
  )

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <PageHeader className="print:hidden" title="Student QR codes" subtitle={`${students.length} active students`}>
        <PrintButton />
      </PageHeader>

      {codes.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground">No active students found.</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4 print:grid-cols-3">
          {codes.map(c => (
            <div
              key={c.id}
              className="bg-white rounded-2xl border border-border p-4 flex flex-col items-center gap-2 break-inside-avoid"
            >
              <div className="w-full aspect-square [&>svg]:w-full [&>svg]:h-full" dangerouslySetInnerHTML={{ __html: c.svg }} />
              <p className="text-sm font-medium text-center leading-tight">{c.fullName}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
