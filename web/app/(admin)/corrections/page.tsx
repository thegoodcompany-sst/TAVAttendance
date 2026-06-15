import { getPendingCorrections } from '@/lib/queries'
import { CorrectionRow } from './correction-row'

export const dynamic = 'force-dynamic'

export default async function CorrectionsPage() {
  const requests = await getPendingCorrections()

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Correction requests</h1>
        <p className="text-sm text-muted-foreground mt-0.5">
          {requests.length} pending request{requests.length !== 1 ? 's' : ''} (PDPA s22)
        </p>
      </div>

      {requests.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
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
