import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'

export const dynamic = 'force-dynamic'

type MessageRow = {
  id: string
  sender_id: string | null
  student_id: string | null
  subject: string | null
  body: string
  sent_at: string
  read_at: string | null
  student: { full_name: string } | null
}

export default async function AdminMessagesPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  const { data: messages } = await supabase
    .from('messages')
    .select('id, sender_id, student_id, subject, body, sent_at, read_at, student:students(full_name)')
    .order('sent_at', { ascending: false })
    .returns<MessageRow[]>()

  // Latest message per student = the thread preview; unread = inbound & not yet read.
  const threads = new Map<string, { name: string; latest: MessageRow; unread: number }>()
  for (const m of messages ?? []) {
    if (!m.student_id) continue
    const existing = threads.get(m.student_id)
    const isUnread = m.read_at === null && m.sender_id !== user?.id
    if (!existing) {
      threads.set(m.student_id, {
        name: m.student?.full_name ?? 'Unknown student',
        latest: m,
        unread: isUnread ? 1 : 0,
      })
    } else if (isUnread) {
      existing.unread += 1
    }
  }

  const list = [...threads.entries()]

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <PageHeader
        title="Messages"
        subtitle={`${list.length} conversation${list.length !== 1 ? 's' : ''}`}
      />

      {list.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground">No messages yet.</p>
        </div>
      ) : (
        <div className="bg-white rounded-3xl shadow-card divide-y divide-border">
          {list.map(([studentId, thread]) => (
            <Link
              key={studentId}
              href={`/messages/${studentId}`}
              prefetch
              className="flex items-center justify-between gap-4 p-5 hover:bg-muted/50 transition-colors"
            >
              <div className="min-w-0">
                <p className="font-medium text-sm">{thread.name}</p>
                <p className="text-xs text-muted-foreground mt-0.5 truncate">{thread.latest.body}</p>
              </div>
              {thread.unread > 0 && (
                <span className="flex-shrink-0 text-xs font-medium text-primary-foreground bg-primary rounded-full px-2 py-0.5">
                  {thread.unread}
                </span>
              )}
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
