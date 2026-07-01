import { createClient } from '@/lib/supabase/server'
import { InviteForm } from './invite-form'
import { RemoveUserButton } from './remove-button'
import { UserPlus, ShieldCheck, BookOpen, Users } from 'lucide-react'
import { PageHeader } from '@/components/dashboard/page-header'

const ROLE_META: Record<string, { label: string; icon: React.ElementType; color: string }> = {
  admin: { label: 'Admin', icon: ShieldCheck, color: 'text-brand bg-brand-soft' },
  tutor: { label: 'Tutor', icon: BookOpen, color: 'text-amber-700 bg-amber-50' },
  parent: { label: 'Parent', icon: Users, color: 'text-sky-700 bg-sky-50' },
}

async function getTeamMembers() {
  const supabase = await createClient()
  const { data } = await supabase
    .from('profiles')
    .select('id, full_name, role, created_at')
    .order('created_at', { ascending: false })
  return data ?? []
}

export default async function UsersPage() {
  const members = await getTeamMembers()

  return (
    <div className="max-w-5xl mx-auto space-y-8">
      <PageHeader
        title="Users"
        subtitle="Invite tutors, parents, and admins. They'll receive an email to set their own password."
      />

      <div className="grid grid-cols-1 lg:grid-cols-[360px_1fr] gap-6 items-start">
        {/* Invite card */}
        <div className="bg-white rounded-2xl border border-border shadow-sm overflow-hidden">
          <div className="h-1.5 w-full bg-brand" />
          <div className="p-6">
            <div className="flex items-center gap-2 mb-5">
              <div className="w-8 h-8 rounded-lg bg-brand-soft flex items-center justify-center">
                <UserPlus size={15} className="text-brand" />
              </div>
              <div>
                <h2 className="text-sm font-semibold text-foreground">Send an invite</h2>
                <p className="text-xs text-muted-foreground">They set their own password</p>
              </div>
            </div>
            <InviteForm />
          </div>
        </div>

        {/* Team members list */}
        <div className="bg-white rounded-2xl border border-border shadow-sm overflow-hidden">
          <div className="px-6 py-4 border-b border-border flex items-center justify-between">
            <h2 className="text-sm font-semibold text-foreground">Team members</h2>
            <span className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded-full">
              {members.length}
            </span>
          </div>

          {members.length === 0 ? (
            <div className="px-6 py-10 text-center text-sm text-muted-foreground">
              No users yet. Send your first invite above.
            </div>
          ) : (
            <ul className="divide-y divide-border">
              {members.map(member => {
                const meta = ROLE_META[member.role] ?? ROLE_META.tutor
                const Icon = meta.icon
                const initials = (member.full_name ?? '?')
                  .split(' ')
                  .map((n: string) => n[0])
                  .slice(0, 2)
                  .join('')
                  .toUpperCase()
                const joinedAt = new Date(member.created_at).toLocaleDateString('en-SG', {
                  day: 'numeric',
                  month: 'short',
                  year: 'numeric',
                })
                return (
                  <li key={member.id} className="group flex items-center gap-4 px-6 py-3.5">
                    {/* Avatar */}
                    <div className="w-9 h-9 rounded-full bg-brand-soft flex items-center justify-center text-brand-ink text-xs font-semibold flex-shrink-0">
                      {initials}
                    </div>
                    {/* Name + date */}
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">
                        {member.full_name ?? '—'}
                      </p>
                      <p className="text-xs text-muted-foreground">Joined {joinedAt}</p>
                    </div>
                    {/* Role badge */}
                    <span className={`inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full ${meta.color}`}>
                      <Icon size={11} />
                      {meta.label}
                    </span>
                    {/* Remove button */}
                    <RemoveUserButton userId={member.id} name={member.full_name ?? 'this user'} />
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  )
}
