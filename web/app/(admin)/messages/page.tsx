import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/dashboard/page-header'
import { Avatar } from '@/components/dashboard/avatar'

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

function relativeTime(iso: string): string {
  const then = new Date(iso).getTime()
  const now = Date.now()
  const mins = Math.round((now - then) / 60_000)
  if (mins < 1) return 'now'
  if (mins < 60) return `${mins}m`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `${hours}h`
  const days = Math.round(hours / 24)
  if (days < 14) return `${days}d`
  return new Intl.DateTimeFormat('en-SG', {
    timeZone: 'Asia/Singapore',
    day: 'numeric',
    month: 'short',
  }).format(new Date(iso))
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
      const parentName = profiles.get(parentId)?.name ?? 'Parent'
      const studentName = m.student?.full_name ?? 'Unknown student'
      threads.set(key, {
        studentId: m.student_id,
        parentId,
        name: `${parentName} · ${studentName}`,
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
        subtitle="Centre ↔ parent threads"
      />

      {list.length === 0 ? (
        <div className="bg-white rounded-[1.25rem] p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground">No messages yet.</p>
        </div>
      ) : (
        <div className="bg-white rounded-[1.25rem] shadow-card overflow-hidden divide-y divide-border">
          {list.map(([key, thread]) => (
            <Link
              key={key}
              href={`/messages/${thread.studentId}?parentId=${thread.parentId}`}
              prefetch
              className="flex items-center gap-4 p-4 sm:px-5 hover:bg-muted/50 transition-colors"
            >
              <Avatar name={thread.name} size="sm" />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <p className="font-bold text-sm text-brand-ink truncate">{thread.name}</p>
                  {thread.unread > 0 ? (
                    <span className="flex-shrink-0 inline-flex min-w-5 h-5 items-center justify-center rounded-full bg-accent-marigold px-1.5 text-[0.6rem] font-black text-accent-marigold-foreground">
                      {thread.unread}
                    </span>
                  ) : (
                    <time className="flex-shrink-0 font-mono text-[0.6rem] text-muted-foreground">
                      {relativeTime(thread.latest.sent_at)}
                    </time>
                  )}
                </div>
                <p className="text-xs text-muted-foreground mt-0.5 truncate">{thread.latest.body}</p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
