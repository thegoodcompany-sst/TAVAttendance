import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'

export type FeatureFlagKey = 'parent_portal' | 'push_notifications' | 'student_photos' | 'study_space_tracking' | 'test_mode' | 'session_notes' | 'qr_sign_in' | 'awards'

/**
 * Reads the `feature_flags` table (migration 012). Flags ship OFF; an admin flips
 * them when a feature is ready. Fails closed: if the table can't be read, every
 * flag is treated as disabled. Request-cached so a page render hits it once.
 */
export const getFeatureFlags = cache(async (): Promise<Record<string, boolean>> => {
  const supabase = await createClient()
  const { data, error } = await supabase.from('feature_flags').select('key, enabled')
  if (error || !data) return {}
  return Object.fromEntries(data.map(f => [f.key as string, f.enabled as boolean]))
})

export async function isFeatureEnabled(key: FeatureFlagKey): Promise<boolean> {
  const flags = await getFeatureFlags()
  return flags[key] === true
}
