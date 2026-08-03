import Link from 'next/link'
import { redirect } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { getMobileProfile } from '@/lib/mobile-queries'
import { NewStudentForm } from '@/app/(admin)/students/new/form'

export default async function NewMobileStudentPage() {
  const profile = await getMobileProfile()
  if (profile?.role !== 'admin') redirect('/mobile/students')
  return <div className="space-y-4"><Link href="/mobile/students" className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> Students</Link><div><p className="text-xs font-black uppercase tracking-[.15em] text-brand/60">Consent required</p><h1 className="font-display text-3xl font-semibold text-brand-ink">Add student</h1></div><div className="rounded-[1.75rem] border border-brand/10 bg-white p-5 shadow-card"><NewStudentForm returnPath="/mobile/students" /></div></div>
}
