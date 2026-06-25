import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'
import { FlagsList, type FlagRow } from './flags-list'

export default async function FeatureFlagsPage() {
  const supabase = await createClient()
  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError) throw authError

  // Hide the route's existence from ordinary admins (the (admin) layout already
  // guarantees user is a signed-in admin).
  if (!isSuperadmin(user)) notFound()

  const { data, error: queryError } = await supabase
    .from('feature_flags')
    .select('key, enabled, description, updated_at')
    .order('key', { ascending: true })
  if (queryError) throw queryError

  const flags = (data ?? []) as FlagRow[]

  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <div>
        <h1 className="text-2xl font-semibold text-foreground tracking-tight">Feature flags</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Toggle in-progress features across iOS, Android, and web. Changes take effect on next load.
        </p>
      </div>

      <div className="bg-white rounded-2xl border border-border shadow-sm overflow-hidden">
        <div className="px-6 py-4 border-b border-border flex items-center justify-between">
          <h2 className="text-sm font-semibold text-foreground">Flags</h2>
          <span className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded-full">
            {flags.length}
          </span>
        </div>
        {flags.length === 0 ? (
          <div className="px-6 py-10 text-center text-sm text-muted-foreground">
            No feature flags defined.
          </div>
        ) : (
          <FlagsList flags={flags} />
        )}
      </div>
    </div>
  )
}
