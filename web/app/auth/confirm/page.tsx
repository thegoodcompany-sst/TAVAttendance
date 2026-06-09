'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { AlertCircle } from 'lucide-react'
import type { EmailOtpType } from '@supabase/supabase-js'

/**
 * Invite / email-link landing page.
 *
 * Supabase invite emails use the IMPLICIT flow by default, which returns the
 * session in the URL *fragment* (`#access_token=...&refresh_token=...`).
 * A server route handler can never read a fragment, so this must run in the
 * browser. We establish the session client-side, then hand off to
 * /set-password. PKCE (`?code=`) and OTP (`?token_hash=`) links are handled
 * too, for robustness.
 */
export default function ConfirmPage() {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const run = async () => {
      const supabase = createClient()
      const url = new URL(window.location.href)
      const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))

      // The link itself may carry an error (expired, already used, etc.)
      const linkError =
        hash.get('error_description') ||
        hash.get('error') ||
        url.searchParams.get('error_description') ||
        url.searchParams.get('error')

      // 1. Implicit flow — tokens in the fragment
      const access_token = hash.get('access_token')
      const refresh_token = hash.get('refresh_token')
      if (access_token && refresh_token) {
        const { error } = await supabase.auth.setSession({ access_token, refresh_token })
        if (error) return setError(error.message)
        return router.replace('/set-password')
      }

      // 2. PKCE flow — ?code=
      const code = url.searchParams.get('code')
      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code)
        if (error) return setError(error.message)
        return router.replace('/set-password')
      }

      // 3. OTP flow — ?token_hash=&type=
      const token_hash = url.searchParams.get('token_hash')
      const type = url.searchParams.get('type') as EmailOtpType | null
      if (token_hash && type) {
        const { error } = await supabase.auth.verifyOtp({ token_hash, type })
        if (error) return setError(error.message)
        return router.replace('/set-password')
      }

      setError(linkError || 'This link is invalid or has already been used.')
    }

    run()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (error) {
    return (
      <div className="min-h-screen bg-surface flex items-center justify-center p-4">
        <div className="w-full max-w-sm text-center space-y-5">
          <div className="w-14 h-14 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
            <AlertCircle className="w-7 h-7 text-destructive" />
          </div>
          <div>
            <h2 className="text-lg font-semibold">Link invalid or expired</h2>
            <p className="text-sm text-muted-foreground mt-1 leading-relaxed">{error}</p>
            <p className="text-sm text-muted-foreground mt-3">Ask your admin to resend the invitation.</p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-surface flex items-center justify-center">
      <p className="text-sm text-muted-foreground animate-pulse">Verifying your invite…</p>
    </div>
  )
}
