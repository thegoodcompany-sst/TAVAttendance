import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getMobileSignInEntries } from '@/lib/mobile-queries'
import { SignInBoard } from '@/components/mobile/sign-in-board'

export const dynamic = 'force-dynamic'

export default async function MobileSignInPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('profiles').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/mobile/classes')
  const entries = await getMobileSignInEntries()
  return <div className="space-y-5"><section><p className="text-xs font-black uppercase tracking-[.16em] text-brand/60">Front desk</p><h1 className="font-display text-3xl font-semibold text-brand-ink">Student sign-in</h1><p className="mt-1 text-sm text-muted-foreground">Tap a card for on-time sign-in; use the smaller controls for overrides.</p></section><SignInBoard initialEntries={entries} /></div>
}
