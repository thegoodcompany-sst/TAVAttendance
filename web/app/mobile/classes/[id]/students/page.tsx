import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { getMobileClass, getMobileEnrollmentData } from '@/lib/mobile-queries'
import { EnrollmentList } from '@/components/mobile/enrollment-list'

export const dynamic = 'force-dynamic'

export default async function MobileEnrollmentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: profile }, classResult, enrollment] = await Promise.all([
    supabase.from('profiles').select('role').eq('id', user!.id).single(),
    getMobileClass(id),
    getMobileEnrollmentData(id),
  ])
  if (profile?.role !== 'admin') redirect(`/mobile/classes/${id}`)
  if (!classResult) notFound()
  return <div className="space-y-4"><Link href={`/mobile/classes/${id}`} className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> {classResult.classInfo.name}</Link><div><p className="text-xs font-black uppercase tracking-[.15em] text-brand/60">Class roster</p><h1 className="font-display text-3xl font-semibold text-brand-ink">Manage students</h1></div><EnrollmentList classId={id} students={enrollment.students} initialEnrolledIds={enrollment.enrolledIds} /></div>
}
