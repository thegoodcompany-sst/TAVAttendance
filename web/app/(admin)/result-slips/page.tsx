import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'
import { AcknowledgeButton } from './acknowledge-button'

export const dynamic = 'force-dynamic'

type SlipRow = {
  id: string
  exam_name: string | null
  exam_date: string | null
  subject: string | null
  score: number | null
  max_score: number | null
  file_path: string | null
  uploaded_at: string
  acknowledged_at: string | null
  student: { full_name: string } | null
}

export default async function AdminResultSlipsPage() {
  const supabase = await createClient()

  const { data: slips } = await supabase
    .from('result_slips')
    .select(
      'id, exam_name, exam_date, subject, score, max_score, file_path, uploaded_at, acknowledged_at, student:students(full_name)',
    )
    .order('uploaded_at', { ascending: false })
    .returns<SlipRow[]>()

  const rows = await Promise.all(
    (slips ?? []).map(async slip => {
      let fileUrl: string | null = null
      if (slip.file_path) {
        const { data } = await supabase.storage
          .from('result-slips')
          .createSignedUrl(slip.file_path, 60 * 60)
        fileUrl = data?.signedUrl ?? null
      }
      return { ...slip, fileUrl }
    }),
  )

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <PageHeader title="Result slips" subtitle={`${rows.length} uploaded`} />

      {rows.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground">No result slips uploaded yet.</p>
        </div>
      ) : (
        <div className="bg-white rounded-3xl shadow-card divide-y divide-border">
          {rows.map(slip => (
            <div key={slip.id} className="p-5 flex items-start justify-between gap-4">
              <div className="min-w-0">
                <p className="font-medium text-sm">{slip.student?.full_name ?? 'Unknown student'}</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {[
                    slip.exam_name,
                    slip.subject,
                    slip.exam_date,
                    slip.score != null && slip.max_score != null
                      ? `${slip.score}/${slip.max_score}`
                      : slip.score != null
                        ? String(slip.score)
                        : null,
                  ]
                    .filter(Boolean)
                    .join(' · ') || '—'}
                </p>
                {slip.fileUrl && (
                  <Link
                    href={slip.fileUrl}
                    target="_blank"
                    className="inline-block mt-2 text-xs font-medium text-brand hover:underline"
                  >
                    View file
                  </Link>
                )}
              </div>
              {slip.acknowledged_at ? (
                <span className="flex-shrink-0 text-xs font-medium text-emerald-700">Acknowledged</span>
              ) : (
                <AcknowledgeButton id={slip.id} />
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
