'use client'

import { useState } from 'react'
import { inviteUser } from '@/app/actions/invite'
import { Button } from '@/components/ui/button'
import { Send, ShieldCheck, BookOpen, Users } from 'lucide-react'

type Role = 'tutor' | 'parent' | 'admin'

const ROLES: { value: Role; label: string; description: string; Icon: React.ElementType }[] = [
  {
    value: 'tutor',
    label: 'Tutor',
    description: 'Can take attendance and manage their assigned classes.',
    Icon: BookOpen,
  },
  {
    value: 'parent',
    label: 'Parent',
    description: 'Can view their child\'s attendance history.',
    Icon: Users,
  },
  {
    value: 'admin',
    label: 'Admin',
    description: 'Full access to the dashboard and all settings.',
    Icon: ShieldCheck,
  },
]

export function InviteForm({ canInviteAdmin = false }: { canInviteAdmin?: boolean }) {
  const [email, setEmail] = useState('')
  const [fullName, setFullName] = useState('')
  const [role, setRole] = useState<Role>('tutor')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSuccess(null)
    setLoading(true)

    const { error: inviteError } = await inviteUser(email, fullName, role)

    setLoading(false)
    if (inviteError) {
      setError(inviteError)
    } else {
      setSuccess(`Invite sent to ${email}`)
      setEmail('')
      setFullName('')
      setRole('tutor')
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <div className="space-y-1.5">
        <label className="text-sm font-medium text-foreground" htmlFor="fullName">
          Full name
        </label>
        <input
          id="fullName"
          type="text"
          required
          value={fullName}
          onChange={e => setFullName(e.target.value)}
          className="w-full rounded-lg border border-input bg-white px-3 py-2.5 text-sm shadow-xs focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20 transition-shadow"
          placeholder="e.g. Wei Lin"
          autoComplete="name"
        />
      </div>

      <div className="space-y-1.5">
        <label className="text-sm font-medium text-foreground" htmlFor="email">
          Email address
        </label>
        <input
          id="email"
          type="email"
          required
          value={email}
          onChange={e => setEmail(e.target.value)}
          className="w-full rounded-lg border border-input bg-white px-3 py-2.5 text-sm shadow-xs focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20 transition-shadow"
          placeholder="they@example.com"
          autoComplete="email"
        />
      </div>

      <div className="space-y-2">
        <span className="text-sm font-medium text-foreground">Role</span>
        <div className="grid gap-2">
          {ROLES.filter(({ value }) => value !== 'admin' || canInviteAdmin).map(({ value, label, description, Icon }) => (
            <button
              key={value}
              type="button"
              onClick={() => setRole(value)}
              className={[
                'w-full text-left rounded-xl border px-4 py-3 flex items-start gap-3 transition-all',
                role === value
                  ? 'border-brand bg-brand-soft ring-2 ring-brand/20'
                  : 'border-border bg-white hover:border-brand/40 hover:bg-surface',
              ].join(' ')}
            >
              <div className={[
                'mt-0.5 w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 transition-colors',
                role === value ? 'bg-brand text-white' : 'bg-muted text-muted-foreground',
              ].join(' ')}>
                <Icon size={15} />
              </div>
              <div className="min-w-0">
                <div className={[
                  'text-sm font-semibold leading-tight transition-colors',
                  role === value ? 'text-brand-ink' : 'text-foreground',
                ].join(' ')}>
                  {label}
                </div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-snug">{description}</div>
              </div>
            </button>
          ))}
        </div>
      </div>

      {error && (
        <p className="text-sm text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-3 py-2.5">
          {error}
        </p>
      )}
      {success && (
        <p className="text-sm text-brand-ink bg-brand-soft border border-brand/20 rounded-lg px-3 py-2.5 flex items-center gap-2">
          <Send size={13} className="flex-shrink-0" />
          {success}
        </p>
      )}

      <Button type="submit" className="w-full gap-2" disabled={loading}>
        <Send size={15} />
        {loading ? 'Sending invite…' : 'Send invite'}
      </Button>
    </form>
  )
}
