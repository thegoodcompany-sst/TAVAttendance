'use server'

import { createAdminClient } from '@/lib/supabase/admin'
import { createClient } from '@/lib/supabase/server'

export async function inviteUser(
  email: string,
  fullName: string,
  role: 'admin' | 'tutor' | 'parent'
): Promise<{ error: string | null }> {
  const serverClient = await createClient()
  const { data: { user } } = await serverClient.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: profile } = await serverClient
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') return { error: 'Only admins can send invites.' }

  const siteUrl = process.env.SITE_URL ?? 'http://localhost:3000'

  const adminClient = createAdminClient()
  const { error } = await adminClient.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName, role },
    redirectTo: `${siteUrl}/auth/confirm`,
  })

  if (error) return { error: error.message }
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
  const { error } = await adminClient.auth.admin.deleteUser(userId)

  if (error) return { error: error.message }
  return { error: null }
}
