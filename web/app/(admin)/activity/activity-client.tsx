'use client'

import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { ChevronRight } from 'lucide-react'
import type { AuditActor, AuditLogEntry, RecentAppEvent } from '@/lib/queries'
import { cn } from '@/lib/utils'

const ACTION_COLOR = {
  INSERT: 'bg-emerald-50 text-emerald-700',
  UPDATE: 'bg-amber-50 text-amber-700',
  DELETE: 'bg-rose-50 text-rose-700',
}

function changedKeys(entry: AuditLogEntry): string {
  if (entry.action === 'INSERT') return 'Created record'
  if (entry.action === 'DELETE') return 'Deleted record'
  const keys = new Set([...Object.keys(entry.oldData ?? {}), ...Object.keys(entry.newData ?? {})])
  const changed = [...keys].filter(key => JSON.stringify(entry.oldData?.[key]) !== JSON.stringify(entry.newData?.[key]))
  return changed.length ? `Changed ${changed.slice(0, 5).join(', ')}${changed.length > 5 ? ` +${changed.length - 5}` : ''}` : 'Updated record'
}

function time(value: string): string {
  return new Date(value).toLocaleString('en-SG', {
    timeZone: 'Asia/Singapore',
    day: 'numeric',
    month: 'short',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export function ActivityClient({
  audit,
  actors,
  events,
}: {
  audit: AuditLogEntry[]
  actors: AuditActor[]
  events: RecentAppEvent[]
}) {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()

  function setFilter(key: string, value?: string) {
    const next = new URLSearchParams(searchParams)
    if (value) next.set(key, value)
    else next.delete(key)
    if (key === 'user' || key === 'table') next.delete('before')
    router.replace(`${pathname}?${next}`)
  }

  const tables = [...new Set(audit.map(entry => entry.tableName))].sort()
  const currentUser = searchParams.get('user') ?? ''
  const currentTable = searchParams.get('table') ?? ''
  const currentPlatform = searchParams.get('platform') ?? ''
  const currentType = searchParams.get('type') ?? ''

  return (
    <div className="space-y-8">
      <section className="bg-white rounded-3xl p-6 shadow-card space-y-5">
        <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-4">
          <div>
            <h2 className="font-display text-lg font-semibold">Who changed what</h2>
            <p className="text-xs text-muted-foreground mt-1">Database writes recorded by the existing audit log</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <select
              aria-label="Filter by user"
              value={currentUser}
              onChange={event => setFilter('user', event.target.value)}
              className="h-9 rounded-xl border border-border bg-white px-3 text-sm"
            >
              <option value="">All users</option>
              {actors.map(actor => <option key={actor.id} value={actor.id}>{actor.fullName}</option>)}
            </select>
            <select
              aria-label="Filter by table"
              value={currentTable}
              onChange={event => setFilter('table', event.target.value)}
              className="h-9 rounded-xl border border-border bg-white px-3 text-sm"
            >
              <option value="">All tables</option>
              {currentTable && !tables.includes(currentTable) && <option value={currentTable}>{currentTable}</option>}
              {tables.map(table => <option key={table} value={table}>{table}</option>)}
            </select>
          </div>
        </div>

        {audit.length === 0 ? (
          <p className="py-12 text-center text-sm text-muted-foreground">No matching changes.</p>
        ) : (
          <div className="divide-y divide-border">
            {audit.map(entry => (
              <div key={entry.id} className="flex flex-col sm:flex-row sm:items-center gap-3 py-3.5">
                <time className="text-xs text-muted-foreground sm:w-32 flex-shrink-0">{time(entry.changedAt)}</time>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{entry.actorName}</p>
                  <p className="text-xs text-muted-foreground truncate">{changedKeys(entry)}</p>
                </div>
                <span className={cn('text-[11px] font-semibold px-2 py-1 rounded-full', ACTION_COLOR[entry.action])}>{entry.action}</span>
                <span className="text-xs font-mono text-muted-foreground sm:w-40 truncate">{entry.tableName}</span>
              </div>
            ))}
          </div>
        )}

        {audit.length === 50 && (
          <button
            onClick={() => setFilter('before', audit.at(-1)?.changedAt)}
            className="inline-flex items-center gap-1 text-sm font-medium text-brand-ink hover:underline"
          >
            Older changes <ChevronRight size={15} />
          </button>
        )}
      </section>

      <section className="bg-white rounded-3xl p-6 shadow-card space-y-5">
        <div>
          <h2 className="font-display text-lg font-semibold">App events</h2>
          <p className="text-xs text-muted-foreground mt-1">Populates after the analytics flag is enabled</p>
        </div>

        <div className="flex flex-wrap gap-2">
          {['', 'ios', 'android', 'web'].map(platform => (
            <button
              key={platform || 'all'}
              onClick={() => setFilter('platform', platform)}
              className={cn('rounded-full px-3 py-1.5 text-xs font-medium border', currentPlatform === platform ? 'bg-brand-soft text-brand-ink border-brand/20' : 'border-border text-muted-foreground')}
            >
              {platform || 'All platforms'}
            </button>
          ))}
          <span className="w-px bg-border mx-1" />
          {['', 'ops', 'screen_view', 'tap', 'error', 'crash'].map(type => (
            <button
              key={type || 'all'}
              onClick={() => setFilter('type', type)}
              className={cn('rounded-full px-3 py-1.5 text-xs font-medium border', currentType === type ? 'bg-brand-soft text-brand-ink border-brand/20' : 'border-border text-muted-foreground')}
            >
              {type ? type.replace('_', ' ') : 'All types'}
            </button>
          ))}
        </div>

        {events.length === 0 ? (
          <p className="py-12 text-center text-sm text-muted-foreground">No app events yet.</p>
        ) : (
          <div className="divide-y divide-border">
            {events.map(event => (
              <div key={event.id} className="grid grid-cols-[110px_80px_1fr] sm:grid-cols-[130px_90px_110px_1fr] gap-3 py-3.5 items-center">
                <time className="text-xs text-muted-foreground">{time(event.occurredAt)}</time>
                <span className="text-xs font-medium uppercase tracking-wide">{event.platform}</span>
                <span className="hidden sm:block text-xs text-muted-foreground">{event.eventType}</span>
                <div className="min-w-0">
                  <p className="text-sm font-medium truncate">{event.name}</p>
                  {Object.keys(event.properties).length > 0 && (
                    <p className="text-xs text-muted-foreground truncate">{JSON.stringify(event.properties)}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
