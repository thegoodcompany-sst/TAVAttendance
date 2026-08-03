import { createClient } from '@/lib/supabase/server'
import { InviteForm } from './invite-form'
import { RemoveUserButton } from './remove-button'
import { ManageChildren } from './manage-children'
import { PageHeader } from '@/components/dashboard/page-header'
import { isSuperadmin } from '@/lib/superadmin'
import { getAllStudents } from '@/lib/queries'
import { cn } from '@/lib/utils'

const ROLE_BADGE: Record<string, { label: string; className: string }> = {
  admin: {
    label: 'Admin',
    className: 'bg-brand-soft text-brand border-[#C5D2EA]',
  },
  tutor: {
    label: 'Tutor',
    className: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  },
  parent: {
    label: 'Parent',
    className: 'bg-slate-100 text-slate-600 border-slate-200',
  },
}

async function getTeamMembers() {
  const supabase = await createClient()
  const { data } = await supabase
    .from('profiles')
    .select('id, full_name, role, created_at')
    .order('created_at', { ascending: false })
  return data ?? []
}

async function getParentStudentLinks() {
  const supabase = await createClient()
  const { data } = await supabase.from('parent_student_links').select('parent_id, student_id')
  return data ?? []
}

export default async function UsersPage() {
  const supabase = await createClient()
  const [members, students, links, superadmin] = await Promise.all([
    getTeamMembers(),
    getAllStudents(),
    getParentStudentLinks(),
    isSuperadmin(supabase),
  ])

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <PageHeader
        title="Users"
        subtitle="Invite staff and manage parent links"
      />

      {/* Draft layout: team table left, invite card right */}
      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_22rem] gap-4 items-start">
        <div className="bg-white rounded-[1.25rem] shadow-card overflow-hidden">
          <div className="flex items-center justify-between border-b border-border px-5 py-4">
            <h2 className="font-display text-[1.1rem] font-semibold text-brand-ink">Team</h2>
            <span className="text-xs text-muted-foreground bg-muted px-2.5 py-0.5 rounded-full font-medium">
              {members.length}
            </span>
          </div>

          {members.length === 0 ? (
            <div className="px-6 py-10 text-center text-sm text-muted-foreground">
              No users yet. Send your first invite.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr>
                    <th className="bg-muted/70 px-5 py-3 text-left text-[0.7rem] font-bold uppercase tracking-wide text-muted-foreground">
                      Name
                    </th>
                    <th className="bg-muted/70 px-5 py-3 text-left text-[0.7rem] font-bold uppercase tracking-wide text-muted-foreground">
                      Role
                    </th>
                    <th className="bg-muted/70 px-5 py-3 text-left text-[0.7rem] font-bold uppercase tracking-wide text-muted-foreground">
                      Joined
                    </th>
                    <th className="bg-muted/70 px-5 py-3 text-right text-[0.7rem] font-bold uppercase tracking-wide text-muted-foreground">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {members.map(member => {
                    const badge = ROLE_BADGE[member.role] ?? ROLE_BADGE.tutor
                    const joinedAt = new Date(member.created_at).toLocaleDateString('en-SG', {
                      timeZone: 'Asia/Singapore',
                      day: 'numeric',
                      month: 'short',
                      year: 'numeric',
                    })
                    const linkedStudentIds = links
                      .filter(l => l.parent_id === member.id)
                      .map(l => l.student_id)
                    const childNames = students
                      .filter(s => linkedStudentIds.includes(s.id))
                      .map(s => s.fullName)

                    return (
                      <tr key={member.id} className="border-t border-border hover:bg-muted/40 transition-colors">
                        <td className="px-5 py-3 align-top">
                          <p className="font-bold text-foreground">{member.full_name ?? '—'}</p>
                          {member.role === 'parent' && (
                            <div className="mt-1.5">
                              {childNames.length > 0 && (
                                <p className="text-xs text-muted-foreground mb-1">
                                  {childNames.join(', ')}
                                </p>
                              )}
                              <ManageChildren
                                parentId={member.id}
                                students={students}
                                linkedStudentIds={linkedStudentIds}
                              />
                            </div>
                          )}
                        </td>
                        <td className="px-5 py-3 align-top">
                          <span
                            className={cn(
                              'inline-flex items-center rounded-full border px-2.5 py-0.5 text-[0.7rem] font-bold',
                              badge.className,
                            )}
                          >
                            {badge.label}
                          </span>
                        </td>
                        <td className="px-5 py-3 align-top text-muted-foreground text-xs">
                          {joinedAt}
                        </td>
                        <td className="px-5 py-3 align-top text-right">
                          <RemoveUserButton
                            userId={member.id}
                            name={member.full_name ?? 'this user'}
                          />
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div className="bg-white rounded-[1.25rem] shadow-card p-5">
          <h2 className="font-display text-[1.1rem] font-semibold text-brand-ink mb-0.5">
            Invite user
          </h2>
          <p className="text-xs text-muted-foreground mb-4">
            Sends a set-password email via Supabase Auth
          </p>
          <InviteForm canInviteAdmin={superadmin} />
        </div>
      </div>
    </div>
  )
}
