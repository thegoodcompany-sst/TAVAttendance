import Link from 'next/link'
import { redirect } from 'next/navigation'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'
import { UploadForm } from './upload-form'

export const dynamic = 'force-dynamic'

export default async function ParentResultsPage({
  params,
}: {
  params: Promise<{ studentId: string }>
}) {
  if (!(await isFeatureEnabled('parent_portal'))) redirect('/parent')

  const { studentId } = await params
  const supabase = await createClient()

  // RLS scopes both queries to the parent's own children.
  const { data: student } = await supabase
    .from('students')
    .select('full_name')
    .eq('id', studentId)
    .maybeSingle()

  const { data: slips } = await supabase
    .from('result_slips')
    .select('id, exam_name, exam_date, subject, score, max_score, file_path, acknowledged_at')
    .eq('student_id', studentId)
    .order('uploaded_at', { ascending: false })

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
    <div className="space-y-6">
      <PageHeader title="Result slips" subtitle={student?.full_name ?? undefined} />

      <div className="bg-white rounded-3xl p-5 shadow-sm">
        <h2 className="font-semibold text-sm mb-3">Upload a slip</h2>
        <UploadForm studentId={studentId} />
      </div>

      {rows.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-sm">
          <p className="text-sm text-muted-foreground">No result slips yet.</p>
        </div>
      ) : (
        <div className="bg-white rounded-3xl shadow-sm divide-y divide-border">
          {rows.map(slip => (
            <div key={slip.id} className="p-5 flex items-start justify-between gap-4">
              <div className="min-w-0">
                <p className="font-medium text-sm">{slip.exam_name ?? 'Result slip'}</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {[
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
              <span
                className={
                  slip.acknowledged_at
                    ? 'flex-shrink-0 text-xs font-medium text-emerald-700'
                    : 'flex-shrink-0 text-xs text-muted-foreground'
                }
              >
                {slip.acknowledged_at ? 'Acknowledged' : 'Pending review'}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
