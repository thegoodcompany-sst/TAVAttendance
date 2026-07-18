import Link from 'next/link'
import { Plus } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { getAllStudents, getStudentResults } from '@/lib/queries'
import { MobileStudentList } from '@/components/mobile/student-list'

export const dynamic = 'force-dynamic'

export default async function MobileStudentsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: profile }, students, results] = await Promise.all([
    supabase.from('profiles').select('role').eq('id', user!.id).single(),
    getAllStudents(),
    getStudentResults(),
  ])
  return <div className="space-y-5"><section className="flex items-end justify-between"><div><p className="text-xs font-black uppercase tracking-[.16em] text-brand/60">Student book</p><h1 className="font-display text-3xl font-semibold text-brand-ink">Students</h1><p className="mt-1 text-sm text-muted-foreground">{students.length} active student{students.length === 1 ? '' : 's'}</p></div>{profile?.role === 'admin' && <Link href="/mobile/students/new" aria-label="Add student" className="grid h-12 w-12 place-items-center rounded-2xl bg-accent-marigold text-brand-ink shadow-card"><Plus size={22} /></Link>}</section><MobileStudentList students={students} results={results} /></div>
}
