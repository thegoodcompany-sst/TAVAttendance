'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  CheckCircle2, Eye, EyeOff, Mail, Lock,
  ShieldCheck, BookOpen, Users, AlertCircle,
} from 'lucide-react'

const ROLE_META: Record<string, { label: string; Icon: React.ElementType; color: string }> = {
  admin:  { label: 'Admin',  Icon: ShieldCheck, color: 'text-brand bg-brand-soft' },
  tutor:  { label: 'Tutor',  Icon: BookOpen,    color: 'text-amber-700 bg-amber-50' },
  parent: { label: 'Parent', Icon: Users,        color: 'text-sky-700 bg-sky-50' },
}

export function SetPasswordForm() {
  const router = useRouter()

  const [email,    setEmail]    = useState('')
  const [fullName, setFullName] = useState('')
  const [role,     setRole]     = useState('')

  const [password,     setPassword]     = useState('')
  const [confirm,      setConfirm]      = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirm,  setShowConfirm]  = useState(false)

  const [error,         setError]         = useState<string | null>(null)
  const [loading,       setLoading]       = useState(false)
  const [sessionReady,  setSessionReady]  = useState(false)
  const [sessionError,  setSessionError]  = useState<string | null>(null)
  const [done,          setDone]          = useState(false)

  useEffect(() => {
    const init = async () => {
      const supabase = createClient()
      // The session was established at /auth/confirm before we got here.
      const { data } = await supabase.auth.getUser()
      if (data.user) {
        setEmail(data.user.email ?? '')
        setFullName(data.user.user_metadata?.full_name ?? '')
        setRole(data.user.user_metadata?.role ?? '')
        setSessionReady(true)
      } else {
        setSessionError('Your invite session has expired. Please use the link from your invitation email again.')
      }
    }

    init()
  }, [])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)

    if (password.length < 8) {
      setError('Password must be at least 8 characters.')
      return
    }
    if (password !== confirm) {
      setError('Passwords do not match.')
      return
    }

    setLoading(true)
    const supabase = createClient()
    const { error: updateError } = await supabase.auth.updateUser({ password })
    if (updateError) {
      setError(updateError.message)
      setLoading(false)
      return
    }
    await supabase.auth.signOut()
    setDone(true)
  }

  const firstName = fullName.split(' ')[0]
  const roleMeta  = ROLE_META[role]

  // ── Loading state ──────────────────────────────────────────────
  if (!sessionReady && !sessionError) {
    return (
      <div className="min-h-screen bg-surface flex items-center justify-center">
        <p className="text-sm text-muted-foreground animate-pulse">Verifying invite…</p>
      </div>
    )
  }

  // ── Error state ────────────────────────────────────────────────
  if (sessionError) {
    return (
      <div className="min-h-screen bg-surface flex items-center justify-center p-4">
        <div className="w-full max-w-sm text-center space-y-5">
          <div className="w-14 h-14 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
            <AlertCircle className="w-7 h-7 text-destructive" />
          </div>
          <div>
            <h2 className="font-display text-xl font-semibold text-brand-ink">Link invalid or expired</h2>
            <p className="text-sm text-muted-foreground mt-1 leading-relaxed">{sessionError}</p>
          </div>
        </div>
      </div>
    )
  }

  // ── Success state ──────────────────────────────────────────────
  if (done) {
    return (
      <div className="min-h-screen bg-surface flex items-center justify-center p-4">
        <div className="w-full max-w-sm">
          <div className="bg-white rounded-2xl border border-border shadow-sm p-8 text-center flex flex-col items-center gap-5">
            <div className="w-16 h-16 rounded-full bg-brand-soft flex items-center justify-center">
              <CheckCircle2 className="w-8 h-8 text-brand" strokeWidth={1.75} />
            </div>
            <div className="space-y-1.5">
              <h2 className="font-display text-xl font-semibold text-brand-ink">
                {firstName ? `You're all set, ${firstName}!` : 'Account activated!'}
              </h2>
              <p className="text-sm text-muted-foreground leading-relaxed">
                Your TAVA account is ready. Sign in on your device using your email and new password.
              </p>
            </div>
            <Button variant="outline" className="w-full" onClick={() => router.push('/login')}>
              Go to sign in
            </Button>
          </div>
        </div>
      </div>
    )
  }

  // ── Main form ──────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-surface flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        {/* Brand */}
        <div className="flex items-center gap-2 mb-8 justify-center">
          <div className="w-9 h-9 rounded-xl bg-brand flex items-center justify-center text-white font-bold text-base">
            T
          </div>
          <span className="font-display font-semibold text-brand text-2xl tracking-tight">TAVA</span>
        </div>

        <div className="bg-white rounded-2xl border border-border shadow-sm overflow-hidden">
          <div className="h-1.5 w-full bg-brand" />

          <div className="p-7 space-y-6">
            {/* Header */}
            <div>
              <h1 className="font-display text-2xl font-semibold text-brand-ink">You&apos;ve been invited</h1>
              <p className="text-sm text-muted-foreground mt-1">
                Create a password to activate your account.
              </p>
            </div>

            {/* Account details card */}
            <div className="bg-surface rounded-xl p-4 space-y-3">
              {fullName && (
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-brand-soft flex items-center justify-center flex-shrink-0 text-xs font-semibold text-brand-ink">
                    {fullName.split(' ').map((n: string) => n[0]).slice(0, 2).join('').toUpperCase()}
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-foreground">{fullName}</p>
                  </div>
                  {roleMeta && (
                    <span className={`ml-auto inline-flex items-center gap-1 text-xs font-medium px-2.5 py-1 rounded-full flex-shrink-0 ${roleMeta.color}`}>
                      <roleMeta.Icon size={11} />
                      {roleMeta.label}
                    </span>
                  )}
                </div>
              )}
              <div className="flex items-center gap-3">
                <div className="w-7 h-7 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
                  <Mail size={13} className="text-muted-foreground" />
                </div>
                <p className="text-sm text-foreground truncate">{email}</p>
              </div>
            </div>

            {/* Password form */}
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground" htmlFor="password">
                  <Lock size={12} className="inline mr-1.5 text-muted-foreground" />
                  New password
                </label>
                <div className="relative">
                  <input
                    id="password"
                    type={showPassword ? 'text' : 'password'}
                    required
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    className="w-full rounded-lg border border-input bg-white px-3 py-2.5 pr-10 text-sm shadow-xs focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20 transition-shadow"
                    placeholder="At least 8 characters"
                    autoComplete="new-password"
                    autoFocus
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(v => !v)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
                    tabIndex={-1}
                  >
                    {showPassword ? <EyeOff size={15} /> : <Eye size={15} />}
                  </button>
                </div>
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground" htmlFor="confirm">
                  Confirm password
                </label>
                <div className="relative">
                  <input
                    id="confirm"
                    type={showConfirm ? 'text' : 'password'}
                    required
                    value={confirm}
                    onChange={e => setConfirm(e.target.value)}
                    className="w-full rounded-lg border border-input bg-white px-3 py-2.5 pr-10 text-sm shadow-xs focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20 transition-shadow"
                    placeholder="Re-enter password"
                    autoComplete="new-password"
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirm(v => !v)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
                    tabIndex={-1}
                  >
                    {showConfirm ? <EyeOff size={15} /> : <Eye size={15} />}
                  </button>
                </div>
              </div>

              {error && (
                <p className="text-sm text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-3 py-2.5">
                  {error}
                </p>
              )}

              <Button type="submit" className="w-full" disabled={loading}>
                {loading ? 'Activating…' : 'Activate account'}
              </Button>
            </form>
          </div>
        </div>
      </div>
    </div>
  )
}
