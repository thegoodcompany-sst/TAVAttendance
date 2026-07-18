import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { getMobileClass } from '@/lib/mobile-queries'
import { MobileClassForm } from '@/components/mobile/class-form'

export default async function EditMobileClassPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: profile }, result] = await Promise.all([supabase.from('profiles').select('role').eq('id', user!.id).single(), getMobileClass(id)])
  if (profile?.role !== 'admin') redirect(`/mobile/classes/${id}`)
  if (!result) notFound()
  return <div className="space-y-4"><Link href={`/mobile/classes/${id}`} className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> {result.classInfo.name}</Link><div><p className="text-xs font-black uppercase tracking-[.15em] text-brand/60">Admin</p><h1 className="font-display text-3xl font-semibold text-brand-ink">Edit class</h1></div><MobileClassForm initial={result.classInfo} /></div>
}
