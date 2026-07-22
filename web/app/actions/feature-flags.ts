'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { isSuperadmin } from '@/lib/superadmin'

export async function setFeatureFlag(
  key: string,
  enabled: boolean
): Promise<{ error: string | null }> {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }
  if (!(await isSuperadmin(supabase))) return { error: 'Not authorized.' }

  // Validate the key exists before writing — types are stripped at runtime so a
  // raw POST could supply anything. Mirrors the runtime guard in invite.ts.
  const { data: existing, error: lookupError } = await supabase
    .from('feature_flags')
    .select('key')
    .eq('key', key)
    .maybeSingle()
  if (lookupError) return { error: lookupError.message }
  if (!existing) return { error: 'Unknown feature flag.' }

  const { error } = await supabase
    .from('feature_flags')
    .update({ enabled, updated_at: new Date().toISOString() })
    .eq('key', key)
  if (error) return { error: error.message }

  revalidatePath('/feature-flags')
  return { error: null }
}
