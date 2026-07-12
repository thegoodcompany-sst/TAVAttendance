'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { wipeOperationalData } from '@/app/actions/wipe'

const PHRASE = 'WIPE ALL DATA'

export function WipeForm() {
  const [value, setValue] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [counts, setCounts] = useState<Record<string, number> | null>(null)

  async function submit() {
    setError(null)
    setCounts(null)
    setPending(true)
    const res = await wipeOperationalData(value)
    setPending(false)
    if (res.error) {
      setError(res.error)
      return
    }
    setCounts(res.counts)
    setValue('')
  }

  return (
    <div className="space-y-4">
      <input
        type="text"
        value={value}
        onChange={e => setValue(e.target.value)}
        placeholder={PHRASE}
        autoComplete="off"
        spellCheck={false}
        disabled={pending}
        className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm font-mono outline-none focus-visible:border-destructive/50 focus-visible:ring-3 focus-visible:ring-destructive/20 disabled:opacity-50"
        aria-label="Confirmation phrase"
      />

      <Button
        variant="destructive"
        size="lg"
        disabled={value !== PHRASE || pending}
        onClick={submit}
      >
        {pending ? 'Wiping…' : 'Wipe all data'}
      </Button>

      {error && (
        <p className="text-sm text-destructive bg-destructive/5 border border-destructive/20 rounded-lg px-3 py-2">
          {error}
        </p>
      )}

      {counts && (
        <div className="rounded-lg border border-border bg-muted px-4 py-3">
          <p className="text-sm font-medium text-foreground mb-2">Wipe complete. Rows deleted:</p>
          <ul className="text-sm text-muted-foreground space-y-0.5">
            {Object.entries(counts).map(([table, n]) => (
              <li key={table} className="flex justify-between gap-4">
                <code className="text-[13px]">{table}</code>
                <span className="tabular-nums text-foreground">{n}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
