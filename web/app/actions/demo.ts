'use server'

import { revalidatePath } from 'next/cache'
import { isDemoEmail } from '@/lib/demo/constants'
import { endDemo, isDemoRequest, startDemo } from '@/lib/demo/state'

/** Signs this browser in to the on-device demo (no Supabase involved). */
export async function enterDemoMode(email: string): Promise<{ error: string | null }> {
  if (!isDemoEmail(email)) return { error: 'Not the demo account.' }
  await startDemo()
  revalidatePath('/', 'layout')
  return { error: null }
}

/** Throws away every demo change and reseeds the demo data. */
export async function resetDemoMode(): Promise<{ error: string | null }> {
  if (!(await isDemoRequest())) return { error: 'Not in demo mode.' }
  await startDemo()
  revalidatePath('/', 'layout')
  return { error: null }
}

/** Leaves demo mode; demo changes are discarded. */
export async function exitDemoMode(): Promise<{ error: string | null }> {
  await endDemo()
  revalidatePath('/', 'layout')
  return { error: null }
}
