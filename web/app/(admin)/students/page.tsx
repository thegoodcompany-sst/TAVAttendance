import Link from 'next/link'
import { QrCode, Plus } from 'lucide-react'
import { getAllStudents, getStudentResults } from '@/lib/queries'
import { isFeatureEnabled } from '@/lib/feature-flags'
import { Avatar } from '@/components/dashboard/avatar'
import { PageHeader } from '@/components/dashboard/page-header'

export const dynamic = 'force-dynamic'

function gradesLabel(results: { subject: string; grade: string }[]) {
  return results.map(r => `${r.subject}: ${r.grade}`).join(' · ')
}

export default async function StudentsPage() {
  const [students, results, showQr] = await Promise.all([
    getAllStudents(),
    getStudentResults(),
    isFeatureEnabled('qr_sign_in'),
  ])
  const gradesByStudent = new Map<string, { subject: string; grade: string }[]>()
  for (const r of results) {
    gradesByStudent.set(r.studentId, [...(gradesByStudent.get(r.studentId) ?? []), r])
  }

  return (
    <div className="max-w-7xl mx-auto space-y-6">
      <PageHeader
        title="Students"
        subtitle={`${students.length} active student${students.length !== 1 ? 's' : ''}`}
      >
        <div className="flex flex-wrap items-center gap-2">
          {showQr && (
            <Link
              href="/students/qr"
              prefetch
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-white/15 bg-white/10 px-3.5 text-sm font-semibold text-white transition-colors hover:bg-white/15"
            >
              <QrCode size={15} /> QR codes
            </Link>
          )}
          <Link
            href="/students/new"
            prefetch
            className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-accent-marigold px-3.5 text-sm font-bold text-accent-marigold-foreground transition-opacity hover:opacity-90"
          >
            <Plus size={15} strokeWidth={2.5} /> Add student
          </Link>
        </div>
      </PageHeader>

      {students.length === 0 ? (
        <div className="bg-white rounded-[1.25rem] p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground mb-4">No active students found.</p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <Link
              href="/students/new"
              prefetch
              className="inline-flex h-9 items-center rounded-lg bg-brand px-4 text-sm font-bold text-primary-foreground"
            >
              Add student
            </Link>
            <Link
              href="/students/import"
              prefetch
              className="inline-flex h-9 items-center rounded-lg border border-border bg-white px-4 text-sm font-semibold hover:bg-muted"
            >
              Import CSV
            </Link>
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {students.map(s => (
            <Link key={s.id} href={`/students/${s.id}`}>
              <article className="bg-white rounded-[1.25rem] p-5 shadow-card hover:shadow-card-lg transition-shadow cursor-pointer group h-full">
                <Avatar name={s.fullName} size="lg" />
                <p className="mt-3 text-sm font-semibold group-hover:text-brand-ink transition-colors">
                  {s.fullName}
                </p>
                {(s.school || s.yearOfStudy) && (
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {[s.school, s.yearOfStudy].filter(Boolean).join(' · ')}
                  </p>
                )}
                {gradesByStudent.has(s.id) && (
                  <p className="text-xs text-brand-ink/70 mt-1.5 font-medium">
                    {gradesLabel(gradesByStudent.get(s.id)!)}
                  </p>
                )}
              </article>
            </Link>
          ))}

          <Link href="/students/new" prefetch>
            <article className="flex min-h-[148px] flex-col items-center justify-center rounded-[1.25rem] border-2 border-dashed border-brand/20 bg-brand-soft/40 p-5 text-center transition-colors hover:border-brand/40 hover:bg-brand-soft/60">
              <div className="grid size-10 place-items-center rounded-full bg-white text-xl font-bold text-brand shadow-card">
                +
              </div>
              <p className="mt-2 text-sm font-semibold text-brand-ink">Add student</p>
              <p className="mt-0.5 text-xs text-muted-foreground">Or import a CSV</p>
            </article>
          </Link>
        </div>
      )}
    </div>
  )
}
