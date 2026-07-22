import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'
import { MessageComposer } from '@/components/message-composer'
import { replyToThread } from '@/app/actions/messages'
import { MarkThreadRead } from './mark-thread-read'

export const dynamic = 'force-dynamic'

export default async function AdminThreadPage({
  params,
  searchParams,
}: {
  params: Promise<{ studentId: string }>
  searchParams: Promise<{ parentId?: string }>
}) {
  const [{ studentId }, { parentId }] = await Promise.all([params, searchParams])
  if (!parentId) notFound()

  const supabase = await createClient()
  const { data: link } = await supabase
    .from('parent_student_links')
    .select('id')
    .eq('student_id', studentId)
    .eq('parent_id', parentId)
    .maybeSingle()
  if (!link) notFound()

  const { data: student } = await supabase
    .from('students')
    .select('full_name')
    .eq('id', studentId)
    .maybeSingle()

  const { data: messages } = await supabase
    .from('messages')
    .select('id, sender_id, subject, body, sent_at')
    .eq('student_id', studentId)
    .or(`sender_id.eq.${parentId},recipient_id.eq.${parentId}`)
    .order('sent_at', { ascending: true })

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <MarkThreadRead studentId={studentId} parentId={parentId} />
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
            const fromCentre = m.sender_id !== parentId
            return (
              <div key={m.id} className={fromCentre ? 'flex justify-end' : 'flex justify-start'}>
                <div
                  className={
                    fromCentre
                      ? 'max-w-[80%] rounded-2xl bg-brand-soft px-4 py-2'
                      : 'max-w-[80%] rounded-2xl bg-muted px-4 py-2'
                  }
                >
                  <p className="text-[11px] font-medium text-muted-foreground mb-0.5">
                    {fromCentre ? 'Centre' : 'Parent'}
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
        <MessageComposer studentId={studentId} recipientId={parentId} action={replyToThread} />
      </div>
    </div>
  )
}
