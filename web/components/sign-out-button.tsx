'use client'

import { createClient, isDemoBrowser } from '@/lib/supabase/client'
import { exitDemoMode } from '@/app/actions/demo'
import { useRouter } from 'next/navigation'

export function SignOutButton() {
  const router = useRouter()
  const handleSignOut = async () => {
    if (isDemoBrowser()) {
      // Signing out of the demo throws away every demo change.
      await exitDemoMode()
      router.push('/login')
      router.refresh()
      return
    }
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }
  return (
    <button
      onClick={handleSignOut}
      className="text-sm text-gray-500 hover:text-gray-900 transition-colors"
    >
      Sign out
    </button>
  )
}
