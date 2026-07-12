import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SignOutButton } from '@/components/sign-out-button'
import { Sidebar } from '@/components/dashboard/sidebar'
import { isSuperadmin } from '@/lib/superadmin'
import { isFeatureEnabled } from '@/lib/feature-flags'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('role, full_name')
    .eq('id', user.id)
    .single()

  // PROD-01: send parents to their own area instead of a dead-end "Access denied".
  if (profile?.role === 'parent') redirect('/parent')

  if (profile?.role !== 'admin') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-surface">
        <div className="text-center max-w-sm">
          <h1 className="text-xl font-semibold mb-2">Access denied</h1>
          <p className="text-sm text-muted-foreground mb-4">This dashboard is for admin accounts only.</p>
          <SignOutButton />
        </div>
      </div>
    )
  }

  const userName = profile.full_name ?? 'Admin'
  const superadmin = isSuperadmin(user)
  const showAwards = await isFeatureEnabled('awards')

  return (
    <div className="flex min-h-screen">
      <Sidebar userName={userName} isSuperadmin={superadmin} showAwards={showAwards} />

      <div className="flex-1 flex flex-col min-h-screen">
        {/* Mobile top nav */}
        <header className="md:hidden print:hidden bg-white border-b border-border h-14 flex items-center justify-between px-4 sticky top-0 z-10">
          <span className="font-display font-semibold text-brand text-xl">TAVA</span>
          <div className="flex items-center gap-2">
            <nav className="flex gap-0.5">
              {[
                { href: '/', label: 'Today' },
                { href: '/overview', label: 'Overview' },
                { href: '/analytics', label: 'Analytics' },
                ...(showAwards ? [{ href: '/awards', label: 'Awards' }] : []),
                { href: '/students', label: 'Students' },
                { href: '/users', label: 'Users' },
                ...(superadmin ? [{ href: '/feature-flags', label: 'Flags' }, { href: '/danger', label: 'Wipe' }] : []),
              ].map(item => (
                <Link
                  key={item.href}
                  href={item.href}
                  prefetch
                  className="px-2.5 py-1.5 text-xs font-medium text-muted-foreground rounded-lg hover:bg-muted transition-colors"
                >
                  {item.label}
                </Link>
              ))}
            </nav>
            <SignOutButton />
          </div>
        </header>

        {/* Desktop top bar */}
        <header className="hidden md:flex print:hidden bg-white border-b border-border h-14 items-center justify-end px-6 sticky top-0 z-10 flex-shrink-0">
          <div className="flex items-center gap-3">
            <span className="text-sm text-muted-foreground">{userName}</span>
            <SignOutButton />
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 bg-surface px-4 sm:px-6 lg:px-8 py-8">
          {children}
        </main>

        {/* Footer */}
        <footer className="print:hidden bg-surface border-t border-border px-4 sm:px-6 lg:px-8 py-4 flex flex-wrap items-center justify-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
          <span>TAVA Attendance</span>
          <span className="text-border">·</span>
          <Link href="/privacy" prefetch className="hover:text-foreground transition-colors">
            Data Protection Notice
          </Link>
          <span className="text-border">·</span>
          <Link href="/corrections" prefetch className="hover:text-foreground transition-colors">
            Correction requests
          </Link>
        </footer>
      </div>
    </div>
  )
}
