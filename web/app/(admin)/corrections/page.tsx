import { getPendingCorrections } from '@/lib/queries'
import { CorrectionRow } from './correction-row'
import { PageHeader } from '@/components/dashboard/page-header'

export const dynamic = 'force-dynamic'

export default async function CorrectionsPage() {
  const requests = await getPendingCorrections()

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <PageHeader
        title="Correction requests"
        subtitle={`${requests.length} pending request${requests.length !== 1 ? 's' : ''} (PDPA s22)`}
      />

      {requests.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground">No pending correction requests.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {requests.map(req => (
            <CorrectionRow key={req.id} request={req} />
          ))}
        </div>
      )}
    </div>
  )
}
