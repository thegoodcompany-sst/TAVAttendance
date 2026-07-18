import Link from 'next/link'
import { redirect } from 'next/navigation'
import { ArrowUpRight } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { SignOutButton } from '@/components/sign-out-button'
import { MobileNav } from '@/components/mobile/mobile-nav'

export default async function MobileLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login?next=/mobile/classes')
  const { data: profile } = await supabase
    .from('profiles')
    .select('role, full_name')
    .eq('id', user.id)
    .single()
  if (profile?.role === 'parent') redirect('/parent')
  if (profile?.role !== 'admin' && profile?.role !== 'tutor') redirect('/login')

  return (
    <div className="mobile-shell min-h-dvh bg-[linear-gradient(180deg,#eef4ff_0,#fffbf2_15rem,#fffbf2_100%)] pb-24">
      <header className="sticky top-0 z-30 border-b border-white/50 bg-[#193775]/95 text-white shadow-[0_8px_30px_rgba(25,55,117,.16)] backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-2xl items-center justify-between px-4">
          <div className="min-w-0">
            <Link href="/mobile/classes" className="font-display text-xl font-semibold tracking-tight">TAVA roll call</Link>
            <p className="truncate text-[11px] font-bold uppercase tracking-[.13em] text-blue-100">{profile.full_name} · {profile.role}</p>
          </div>
          <div className="flex items-center gap-1">
            {profile.role === 'admin' && (
              <Link href="/" aria-label="Open desktop dashboard" className="grid h-10 w-10 place-items-center rounded-xl text-blue-100 hover:bg-white/10 hover:text-white">
                <ArrowUpRight size={19} />
              </Link>
            )}
            <SignOutButton />
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-2xl px-4 py-5">{children}</main>
      <MobileNav isAdmin={profile.role === 'admin'} />
    </div>
  )
}
