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
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  if (!parentId || !UUID_RE.test(parentId) || !UUID_RE.test(studentId)) notFound()

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

  // Bound values only after UUID validation so PostgREST .or() never sees free text.
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

      <div className="bg-white rounded-[1.25rem] shadow-card overflow-hidden">
        <div className="space-y-3 bg-surface/50 p-5 min-h-[12rem]">
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
                        ? 'max-w-[80%] rounded-2xl rounded-tr-sm bg-brand px-3.5 py-2.5 text-primary-foreground shadow-card'
                        : 'max-w-[80%] rounded-2xl rounded-tl-sm border border-border bg-white px-3.5 py-2.5 shadow-card'
                    }
                  >
                    {m.subject && (
                      <p className={`text-sm font-semibold mb-0.5 ${fromCentre ? 'text-white' : ''}`}>
                        {m.subject}
                      </p>
                    )}
                    <p className={`text-sm whitespace-pre-wrap ${fromCentre ? 'text-white/95' : ''}`}>
                      {m.body}
                    </p>
                    <time
                      className={`mt-1.5 block font-mono text-[0.6rem] ${
                        fromCentre ? 'text-white/65' : 'text-muted-foreground'
                      }`}
                    >
                      {new Intl.DateTimeFormat('en-SG', {
                        timeZone: 'Asia/Singapore',
                        hour: '2-digit',
                        minute: '2-digit',
                      }).format(new Date(m.sent_at))}
                    </time>
                  </div>
                </div>
              )
            })
          )}
        </div>
        <div className="border-t border-border p-4">
          <MessageComposer studentId={studentId} recipientId={parentId} action={replyToThread} />
        </div>
      </div>
    </div>
  )
}
