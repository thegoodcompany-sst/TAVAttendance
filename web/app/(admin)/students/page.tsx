import Link from 'next/link'
import { getAllStudents, getStudentResults } from '@/lib/queries'
import { Avatar } from '@/components/dashboard/avatar'
import { PageHeader } from '@/components/dashboard/page-header'

export const dynamic = 'force-dynamic'

function gradesLabel(results: { subject: string; grade: string }[]) {
  return results.map(r => `${r.subject}: ${r.grade}`).join(' · ')
}

export default async function StudentsPage() {
  const [students, results] = await Promise.all([getAllStudents(), getStudentResults()])
  const gradesByStudent = new Map<string, { subject: string; grade: string }[]>()
  for (const r of results) {
    gradesByStudent.set(r.studentId, [...(gradesByStudent.get(r.studentId) ?? []), r])
  }

  return (
    <div className="max-w-7xl mx-auto space-y-6">
      <PageHeader
        title="Students"
        subtitle={`${students.length} active student${students.length !== 1 ? 's' : ''}`}
      />

      {students.length === 0 ? (
        <div className="bg-white rounded-3xl p-12 text-center shadow-card">
          <p className="text-sm text-muted-foreground">No active students found.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {students.map(s => (
            <Link key={s.id} href={`/students/${s.id}`}>
              <div className="bg-white rounded-3xl p-5 shadow-card hover:shadow-card-lg transition-shadow cursor-pointer group">
                <Avatar name={s.fullName} size="lg" />
                <div className="mt-3">
                  <p className="font-semibold text-sm group-hover:text-brand-ink transition-colors">
                    {s.fullName}
                  </p>
                  {(s.school || s.yearOfStudy) && (
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {[s.school, s.yearOfStudy].filter(Boolean).join(' · ')}
                    </p>
                  )}
                  {gradesByStudent.has(s.id) && (
                    <p className="text-xs text-brand-ink/70 mt-1 font-medium">
                      {gradesLabel(gradesByStudent.get(s.id)!)}
                    </p>
                  )}
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
