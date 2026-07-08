'use server'

import 'server-only'
import { createAdminClient } from '@/lib/supabase/admin'
import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'

// Base URL for invite redirect links. In production a missing SITE_URL would
// silently ship localhost links that dead-end every invitee, so require it.
function resolveSiteUrl(): { url: string | null; error: string | null } {
  const explicit = process.env.SITE_URL
  if (explicit) return { url: explicit, error: null }
  const vercel = process.env.VERCEL_PROJECT_PRODUCTION_URL
  if (vercel) return { url: `https://${vercel}`, error: null }
  if (process.env.NODE_ENV === 'production') {
    return { url: null, error: 'SITE_URL is not configured — cannot send a valid invite link.' }
  }
  return { url: 'http://localhost:3000', error: null }
}

export async function inviteUser(
  email: string,
  fullName: string,
  role: 'admin' | 'tutor' | 'parent'
): Promise<{ error: string | null }> {
  // SP-04: runtime guard — TypeScript types are stripped at runtime so a raw
  // POST could supply an arbitrary string. Reject anything not in the allowed
  // set before any DB interaction.
  if (!(['admin', 'tutor', 'parent'] as string[]).includes(role)) {
    return { error: 'Invalid role.' }
  }

  const serverClient = await createClient()
  const { data: { user } } = await serverClient.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: profile } = await serverClient
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') return { error: 'Only admins can send invites.' }

  const adminClient = createAdminClient()

  // PDPA-PR3: rate-limit invites to curb email enumeration by a compromised
  // admin. The rate_limit_events table is RLS-locked to service_role, so it is
  // only reachable via this admin client. Allow at most 20 invites per actor
  // in any rolling 1-hour window.
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  const { count, error: countError } = await adminClient
    .from('rate_limit_events')
    .select('id', { count: 'exact', head: true })
    .eq('actor_id', user.id)
    .eq('action', 'invite')
    .gt('created_at', oneHourAgo)

  if (countError) return { error: countError.message }
  if ((count ?? 0) >= 20) {
    return { error: 'Invite rate limit reached. Please try again later (max 20 invites per hour).' }
  }

  const { error: rlError } = await adminClient
    .from('rate_limit_events')
    .insert({ actor_id: user.id, action: 'invite' })
  if (rlError) return { error: rlError.message }

  const { url: siteUrl, error: siteUrlError } = resolveSiteUrl()
  if (siteUrlError || !siteUrl) return { error: siteUrlError ?? 'SITE_URL misconfigured.' }

  const { data: invited, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName, role },
    redirectTo: `${siteUrl}/auth/confirm`,
  })

  if (error) return { error: error.message }

  // The handle_new_user trigger creates every invited user as 'parent' (least
  // privilege) because metadata role is no longer trusted (migration 016). Set
  // the intended role authoritatively here — the service-role client bypasses RLS.
  if (invited?.user) {
    const { error: roleError } = await adminClient
      .from('profiles')
      .update({ role })
      .eq('id', invited.user.id)
    if (roleError) return { error: `Invite sent but role assignment failed: ${roleError.message}` }
  }

  return { error: null }
}

export async function removeUser(userId: string): Promise<{ error: string | null }> {
  const serverClient = await createClient()
  const { data: { user } } = await serverClient.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  if (user.id === userId) return { error: 'You cannot remove your own account.' }

  const { data: profile } = await serverClient
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') return { error: 'Only admins can remove users.' }

  const adminClient = createAdminClient()

  // Guard: a plain admin must not be able to delete another admin (or the
  // superadmin who controls feature flags). Only the superadmin may remove admins.
  const { data: target } = await adminClient
    .from('profiles')
    .select('role')
    .eq('id', userId)
    .maybeSingle()
  if (target?.role === 'admin' && !isSuperadmin(user)) {
    return { error: 'Only the superadmin can remove another admin account.' }
  }

  const { error } = await adminClient.auth.admin.deleteUser(userId)

  if (error) return { error: error.message }
  return { error: null }
}
