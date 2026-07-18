import Link from 'next/link'
import { redirect } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { MobileClassForm } from '@/components/mobile/class-form'

export default async function NewMobileClassPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('profiles').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/mobile/classes')
  return <div className="space-y-4"><Link href="/mobile/classes" className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-brand"><ArrowLeft size={18} /> Classes</Link><div><p className="text-xs font-black uppercase tracking-[.15em] text-brand/60">Admin</p><h1 className="font-display text-3xl font-semibold text-brand-ink">Add class</h1></div><MobileClassForm /></div>
}
