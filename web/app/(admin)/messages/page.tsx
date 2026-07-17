import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'

export const dynamic = 'force-dynamic'

type MessageRow = {
  id: string
  sender_id: string | null
  recipient_id: string | null
  student_id: string | null
  subject: string | null
  body: string
  sent_at: string
  read_at: string | null
  student: { full_name: string } | null
}

export default async function AdminMessagesPage() {
  const supabase = await createClient()
  const { data: messages } = await supabase
    .from('messages')
    .select('id, sender_id, recipient_id, student_id, subject, body, sent_at, read_at, student:students(full_name)')
    .order('sent_at', { ascending: false })
    .returns<MessageRow[]>()

  const participantIds = [...new Set((messages ?? []).flatMap(m => [m.sender_id, m.recipient_id].filter((id): id is string => Boolean(id))))]
  const profiles = new Map<string, { role: string; name: string }>()
  if (participantIds.length > 0) {
    const { data } = await supabase.from('profiles').select('id, role, full_name').in('id', participantIds)
    for (const profile of data ?? []) profiles.set(profile.id, { role: profile.role, name: profile.full_name })
  }

  const threads = new Map<string, { studentId: string; parentId: string; name: string; latest: MessageRow; unread: number }>()
  for (const m of messages ?? []) {
    if (!m.student_id) continue
    const parentId = m.sender_id && profiles.get(m.sender_id)?.role === 'parent' ? m.sender_id : m.recipient_id
    if (!parentId) continue
    const key = `${m.student_id}:${parentId}`
    const existing = threads.get(key)
    const isUnread = m.read_at === null && m.sender_id === parentId
    if (!existing) {
      threads.set(key, {
        studentId: m.student_id,
        parentId,
        name: `${m.student?.full_name ?? 'Unknown student'} · ${profiles.get(parentId)?.name ?? 'Parent'}`,
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
          {list.map(([key, thread]) => (
            <Link
              key={key}
              href={`/messages/${thread.studentId}?parentId=${thread.parentId}`}
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
