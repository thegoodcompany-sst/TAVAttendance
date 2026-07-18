import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { getStudent, getStudentClassSummary, getStudentRecentRecords, getStudentResults } from '@/lib/queries'
import { statusLabel, statusColor } from '@/lib/status'
import { StudentDetailActions } from '@/components/mobile/student-detail-actions'

export const dynamic = 'force-dynamic'

export default async function MobileStudentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: profile }, student, summaries, records, results] = await Promise.all([
    supabase.from('profiles').select('role').eq('id', user!.id).single(),
    getStudent(id),
    getStudentClassSummary(id),
    getStudentRecentRecords(id),
    getStudentResults(id),
  ])
  if (!student) notFound()
  return <div className="space-y-5">
    <Link href="/mobile/students" className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> Students</Link>
    <section className="rounded-[2rem] bg-brand p-6 text-white shadow-[0_18px_40px_rgba(25,55,117,.22)]">
      <div className="grid h-16 w-16 place-items-center rounded-2xl bg-white/15 font-display text-2xl font-bold">{student.full_name.split(/\s+/).slice(0,2).map((part: string) => part[0]).join('').toUpperCase()}</div>
      <h1 className="mt-4 font-display text-3xl font-semibold leading-tight">{student.full_name}</h1>
      <p className="mt-1 text-sm text-blue-100">{[student.school, student.year_of_study].filter(Boolean).join(' · ') || 'No school details'}</p>
      {student.notes && <p className="mt-4 rounded-xl bg-white/10 px-3 py-2 text-sm text-blue-50">{student.notes}</p>}
    </section>

    <StudentDetailActions student={student} initialResults={results} isAdmin={profile?.role === 'admin'} />

    <section><h2 className="mb-3 text-xs font-black uppercase tracking-[.14em] text-brand/60">Attendance by class</h2><div className="overflow-hidden rounded-[1.5rem] border border-brand/10 bg-white shadow-card">{summaries.length ? summaries.map(summary => <div key={summary.classId} className="flex min-h-16 items-center gap-3 border-b border-brand/8 px-4 last:border-0"><div className="min-w-0 flex-1"><p className="truncate font-bold text-brand-ink">{summary.className}</p><p className="text-xs text-muted-foreground">{summary.totalSessions} sessions · {summary.presentCount} present · {summary.lateCount} late</p></div><p className="font-mono text-lg font-black text-brand">{summary.attendancePct === null ? '—' : `${summary.attendancePct}%`}</p></div>) : <p className="p-7 text-center text-sm text-muted-foreground">No attendance yet.</p>}</div></section>

    <section><h2 className="mb-3 text-xs font-black uppercase tracking-[.14em] text-brand/60">Recent register</h2><div className="space-y-2">{records.slice(0, 12).map(record => <div key={record.id} className="flex items-center gap-3 rounded-2xl border border-brand/10 bg-white p-4 shadow-card"><div className="min-w-0 flex-1"><p className="font-bold text-brand-ink">{record.className}</p><p className="font-mono text-xs text-muted-foreground">{record.sessionDate}</p></div><span className={`rounded-full border px-2.5 py-1 text-xs font-bold ${statusColor(record.status)}`}>{statusLabel(record.status)}</span></div>)}{records.length === 0 && <p className="rounded-2xl bg-white p-7 text-center text-sm text-muted-foreground shadow-card">No records yet.</p>}</div></section>
  </div>
}
