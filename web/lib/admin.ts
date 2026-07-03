import { createClient } from '@/lib/supabase/server'

// NRIC/FIN pattern — mirrors the server-side DB trigger reject_nric_in_notes()
// so we can give a friendly message before hitting the database.
export const NRIC_RE = /\b[STFGM][0-9]{7}[A-Z]\b/i

/** Shared auth gate for admin-only server actions. */
export async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' as const, supabase, user: null }

  const { data: profile } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') {
    return { error: 'Only admins can perform this action.' as const, supabase, user: null }
  }
  return { error: null, supabase, user }
}
