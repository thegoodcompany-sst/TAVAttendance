import { notFound, redirect } from 'next/navigation'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { getParentChild } from '@/lib/parent-queries'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'
import { MessageComposer } from '@/components/message-composer'
import { sendParentMessage } from '@/app/actions/parent-portal'

export const dynamic = 'force-dynamic'

type ParentMessageRow = {
  id: string
  subject: string | null
  body: string
  is_from_parent: boolean
}

export default async function ParentMessagesPage({
  params,
}: {
  params: Promise<{ studentId: string }>
}) {
  if (!(await isFeatureEnabled('parent_portal'))) redirect('/parent')

  const { studentId } = await params
  const supabase = await createClient()
  const student = await getParentChild(studentId)
  if (!student) notFound()

  const { data: messages } = await supabase
    .rpc('get_parent_messages', { p_student_id: studentId })
  const messageRows = (messages ?? []) as ParentMessageRow[]

  return (
    <div className="space-y-6">
      <PageHeader title="Messages" subtitle={student.fullName} />

      <div className="bg-white rounded-3xl p-5 shadow-sm space-y-3">
        {messageRows.length === 0 ? (
          <p className="text-sm text-muted-foreground">No messages yet. Start the conversation below.</p>
        ) : (
          messageRows.map(m => {
            const mine = m.is_from_parent
            return (
              <div key={m.id} className={mine ? 'flex justify-end' : 'flex justify-start'}>
                <div
                  className={
                    mine
                      ? 'max-w-[80%] rounded-2xl bg-brand-soft px-4 py-2'
                      : 'max-w-[80%] rounded-2xl bg-muted px-4 py-2'
                  }
                >
                  <p className="text-[11px] font-medium text-muted-foreground mb-0.5">
                    {mine ? 'You' : 'TAVA'}
                  </p>
                  {m.subject && <p className="text-sm font-semibold">{m.subject}</p>}
                  <p className="text-sm whitespace-pre-wrap">{m.body}</p>
                </div>
              </div>
            )
          })
        )}
      </div>

      <div className="bg-white rounded-3xl p-5 shadow-sm">
        <MessageComposer studentId={studentId} action={sendParentMessage} />
      </div>
    </div>
  )
}
