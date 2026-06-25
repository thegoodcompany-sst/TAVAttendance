'use client'

import { useState } from 'react'
import { Switch } from '@/components/ui/switch'
import { setFeatureFlag } from '@/app/actions/feature-flags'

export interface FlagRow {
  key: string
  enabled: boolean
  description: string | null
  updated_at: string
}

function humanize(key: string): string {
  const s = key.replace(/_/g, ' ')
  return s.charAt(0).toUpperCase() + s.slice(1)
}

export function FlagsList({ flags }: { flags: FlagRow[] }) {
  return (
    <ul className="divide-y divide-border">
      {flags.map(flag => (
        <FlagItem key={flag.key} flag={flag} />
      ))}
    </ul>
  )
}

function FlagItem({ flag }: { flag: FlagRow }) {
  const [enabled, setEnabled] = useState(flag.enabled)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const updatedAt = new Date(flag.updated_at).toLocaleDateString('en-SG', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })

  async function toggle(next: boolean) {
    setError(null)
    setEnabled(next) // optimistic
    setPending(true)
    const { error: actionError } = await setFeatureFlag(flag.key, next)
    setPending(false)
    if (actionError) {
      setEnabled(!next) // revert
      setError(actionError)
    }
  }

  return (
    <li className="flex items-start gap-4 px-6 py-4">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-foreground">{humanize(flag.key)}</p>
          <code className="text-[11px] text-muted-foreground bg-muted px-1.5 py-0.5 rounded">
            {flag.key}
          </code>
        </div>
        {flag.description && (
          <p className="text-xs text-muted-foreground mt-0.5 leading-snug">{flag.description}</p>
        )}
        <p className="text-[11px] text-muted-foreground mt-1">Updated {updatedAt}</p>
        {error && (
          <p className="text-xs text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-2.5 py-1.5 mt-2">
            {error}
          </p>
        )}
      </div>
      <div className="pt-0.5">
        <Switch
          checked={enabled}
          onCheckedChange={toggle}
          disabled={pending}
          aria-label={`Toggle ${humanize(flag.key)}`}
        />
      </div>
    </li>
  )
}
