import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SignOutButton } from '@/components/sign-out-button'
import { Sidebar } from '@/components/dashboard/sidebar'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('role, full_name')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-surface">
        <div className="text-center max-w-sm">
          <h1 className="text-xl font-semibold mb-2">Access denied</h1>
          <p className="text-sm text-muted-foreground mb-4">This dashboard is for admin accounts only.</p>
          <form action="/api/auth/signout" method="post">
            <SignOutButton />
          </form>
        </div>
      </div>
    )
  }

  const userName = profile.full_name ?? 'Admin'

  return (
    <div className="flex min-h-screen">
      <Sidebar userName={userName} />

      <div className="flex-1 flex flex-col min-h-screen">
        {/* Mobile top nav */}
        <header className="md:hidden bg-white border-b border-border h-14 flex items-center justify-between px-4 sticky top-0 z-10">
          <span className="font-bold text-brand text-lg">TAVA</span>
          <div className="flex items-center gap-2">
            <nav className="flex gap-0.5">
              {[
                { href: '/', label: 'Today' },
                { href: '/overview', label: 'Overview' },
                { href: '/students', label: 'Students' },
                { href: '/users', label: 'Users' },
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
        <header className="hidden md:flex bg-white border-b border-border h-14 items-center justify-between px-6 sticky top-0 z-10 flex-shrink-0">
          <div className="pl-9 pr-4 py-2 bg-muted rounded-full text-sm text-muted-foreground w-60 cursor-default select-none">
            Search…
          </div>
          <div className="flex items-center gap-3">
            <span className="text-sm text-muted-foreground">{userName}</span>
            <SignOutButton />
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 bg-surface px-4 sm:px-6 lg:px-8 py-8">
          {children}
        </main>
      </div>
    </div>
  )
}
