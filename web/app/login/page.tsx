'use client'

import { useState, useEffect, useRef } from 'react'
import Image from 'next/image'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [handlingInvite, setHandlingInvite] = useState(false)
  const inviteHandled = useRef(false)
  const router = useRouter()

  // Supabase invite/recovery links use the implicit flow: the session arrives
  // in the URL fragment (#access_token=...&type=invite). Supabase often drops
  // the user on the Site URL (which lands here on /login) rather than our
  // redirect target, so we catch the fragment here, establish the session, and
  // forward to /set-password.
  useEffect(() => {
    if (inviteHandled.current) return
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
    const access_token = hash.get('access_token')
    const refresh_token = hash.get('refresh_token')
    const type = hash.get('type')

    if (access_token && refresh_token && (type === 'invite' || type === 'recovery' || type === 'signup')) {
      inviteHandled.current = true
      // Run in an async callback (not the effect body) so the setState calls
      // aren't synchronous-in-effect (react-hooks/set-state-in-effect).
      void (async () => {
        setHandlingInvite(true)
        const supabase = createClient()
        const { error } = await supabase.auth.setSession({ access_token, refresh_token })
        if (error) {
          setHandlingInvite(false)
          setError('Your invite link is invalid or has expired. Ask your admin to resend it.')
          return
        }
        // Clear the fragment so a refresh doesn't re-trigger this.
        window.history.replaceState(null, '', '/login')
        router.replace('/set-password')
      })()
    }
  }, [router])

  if (handlingInvite) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-surface p-4">
        <p className="text-sm text-muted-foreground animate-pulse">Verifying your invite…</p>
      </div>
    )
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    const supabase = createClient()
    const { data, error: authError } = await supabase.auth.signInWithPassword({ email, password })

    if (authError) {
      setError(authError.message)
      setLoading(false)
      return
    }

    // Route each authenticated role to its least-privileged application shell.
    const { data: profile } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', data.user.id)
      .single()

    if (profile?.role === 'parent') {
      router.push('/parent')
      router.refresh()
      return
    }

    if (profile?.role === 'tutor') {
      router.push('/mobile/classes')
      router.refresh()
      return
    }

    if (profile?.role !== 'admin') {
      await supabase.auth.signOut()
      setError('This account does not have an application role.')
      setLoading(false)
      return
    }

    router.push('/')
    router.refresh()
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface p-4">
      <Card className="w-full max-w-sm shadow-card-lg border-border/60">
        <CardHeader className="space-y-1 pb-4">
          <div className="mb-2">
            <Image
              src="/tava-logo.png"
              alt="TAVA"
              width={140}
              height={74}
              priority
              className="h-12 w-auto"
            />
          </div>
          <CardTitle className="font-display text-2xl font-semibold text-brand-ink">Welcome back</CardTitle>
          <CardDescription>Admin, tutor, and parent accounts</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1">
              <label className="text-sm font-medium text-foreground" htmlFor="email">
                Email
              </label>
              <input
                id="email"
                type="email"
                required
                value={email}
                onChange={e => setEmail(e.target.value)}
                className="w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/40"
                placeholder="you@example.com"
                autoComplete="email"
              />
            </div>
            <div className="space-y-1">
              <label className="text-sm font-medium text-foreground" htmlFor="password">
                Password
              </label>
              <input
                id="password"
                type="password"
                required
                value={password}
                onChange={e => setPassword(e.target.value)}
                className="w-full rounded-lg border border-border px-3 py-2 text-sm shadow-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/40"
                autoComplete="current-password"
              />
            </div>
            {error && (
              <p className="text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">
                {error}
              </p>
            )}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Signing in…' : 'Sign in'}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
