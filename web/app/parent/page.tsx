import { isFeatureEnabled } from '@/lib/feature-flags'
import { getAllStudents, getStudentClassSummary } from '@/lib/queries'
import { Avatar } from '@/components/dashboard/avatar'
import { PageHeader } from '@/components/dashboard/page-header'

export const dynamic = 'force-dynamic'

export default async function ParentPage() {
  // PROD-01: gated by the parent_portal flag. Until an admin enables it, parents
  // see a "being prepared" placeholder rather than a half-built portal.
  if (!(await isFeatureEnabled('parent_portal'))) {
    return (
      <div className="bg-white rounded-3xl p-12 text-center shadow-sm">
        <h1 className="text-xl font-semibold mb-2">Coming soon</h1>
        <p className="text-sm text-muted-foreground">
          Your child&apos;s attendance history is being prepared. You&apos;ll be able to view it here soon.
        </p>
      </div>
    )
  }

  // RLS limits a parent to their own children (students: parent can read own children).
  const children = await getAllStudents()

  return (
    <div className="space-y-6">
      <PageHeader title="My children" />


      {children.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-sm">
          <p className="text-sm text-muted-foreground">
            No students are linked to your account yet. Please contact the centre.
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {await Promise.all(children.map(async child => {
            const summary = await getStudentClassSummary(child.id)
            return (
              <div key={child.id} className="bg-white rounded-3xl p-5 shadow-sm">
                <div className="flex items-center gap-3 mb-4">
                  <Avatar name={child.fullName} />
                  <div>
                    <p className="font-semibold">{child.fullName}</p>
                    {child.yearOfStudy && (
                      <p className="text-xs text-muted-foreground">{child.yearOfStudy}</p>
                    )}
                  </div>
                </div>
                {summary.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No attendance recorded yet.</p>
                ) : (
                  <ul className="space-y-2">
                    {summary.map(c => (
                      <li key={c.classId} className="flex items-center justify-between text-sm">
                        <span>{c.className}</span>
                        <span className="text-muted-foreground">
                          {c.attendancePct === null ? '—' : `${c.attendancePct}%`} · {c.totalSessions} sessions
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )
          }))}
        </div>
      )}
    </div>
  )
}
