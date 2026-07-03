import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SignOutButton } from '@/components/sign-out-button'

// PROD-01 — parent-facing area. Separate from the admin dashboard group so parents
// have somewhere to land instead of the "Access denied" screen. The content is
// further gated by the `parent_portal` feature flag inside the page.
export default async function ParentLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('role, full_name')
    .eq('id', user.id)
    .single()

  // Admins use the dashboard; only parents belong here.
  if (profile?.role === 'admin') redirect('/')
  if (profile?.role !== 'parent') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-surface">
        <div className="text-center max-w-sm">
          <h1 className="text-xl font-semibold mb-2">Access denied</h1>
          <p className="text-sm text-muted-foreground mb-4">This area is for parent accounts.</p>
          <SignOutButton />
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-surface">
      <header className="bg-white border-b border-border h-14 flex items-center justify-between px-4">
        <span className="font-display font-semibold text-brand text-xl">TAVA</span>
        <SignOutButton />
      </header>
      <main className="max-w-3xl mx-auto p-4 md:p-6">{children}</main>
    </div>
  )
}
