import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'
import { MessageComposer } from '@/components/message-composer'
import { replyToThread } from '@/app/actions/messages'

export const dynamic = 'force-dynamic'

export default async function AdminThreadPage({
  params,
}: {
  params: Promise<{ studentId: string }>
}) {
  const { studentId } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  // Mark inbound messages in this thread as read (admin FOR ALL policy allows it).
  await supabase
    .from('messages')
    .update({ read_at: new Date().toISOString() })
    .eq('student_id', studentId)
    .is('read_at', null)
    .neq('sender_id', user!.id)

  const { data: student } = await supabase
    .from('students')
    .select('full_name')
    .eq('id', studentId)
    .maybeSingle()

  const { data: messages } = await supabase
    .from('messages')
    .select('id, sender_id, subject, body, sent_at')
    .eq('student_id', studentId)
    .order('sent_at', { ascending: true })

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader title={student?.full_name ?? 'Conversation'} subtitle="Message thread" />

      <Link
        href="/messages"
        prefetch
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft size={14} /> All conversations
      </Link>

      <div className="bg-white rounded-3xl p-5 shadow-card space-y-3">
        {(messages ?? []).length === 0 ? (
          <p className="text-sm text-muted-foreground">No messages in this conversation.</p>
        ) : (
          (messages ?? []).map(m => {
            const mine = m.sender_id === user?.id
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
                    {mine ? 'Centre' : 'Parent'}
                  </p>
                  {m.subject && <p className="text-sm font-semibold">{m.subject}</p>}
                  <p className="text-sm whitespace-pre-wrap">{m.body}</p>
                </div>
              </div>
            )
          })
        )}
      </div>

      <div className="bg-white rounded-3xl p-5 shadow-card">
        <MessageComposer studentId={studentId} action={replyToThread} />
      </div>
    </div>
  )
}
