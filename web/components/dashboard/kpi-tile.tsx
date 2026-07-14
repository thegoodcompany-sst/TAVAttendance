import { cn } from '@/lib/utils'

type KpiTileProps = {
  label: string
  value: number | string
  delta?: number
  deltaLabel?: string
  status?: 'green' | 'amber' | 'red'
  lowerIsBetter?: boolean
  accent?: boolean
}

const STATUS_COLOR = {
  green: 'bg-emerald-500',
  amber: 'bg-amber-500',
  red: 'bg-rose-500',
}

export function KpiTile({ label, value, delta, deltaLabel, status, lowerIsBetter = false, accent }: KpiTileProps) {
  return (
    <div
      className={cn(
        'rounded-3xl p-5',
        accent
          ? 'bg-brand-soft'
          : 'bg-white shadow-card'
      )}
    >
      <div className="flex items-center gap-2 mb-2">
        {status && (
          <>
            <span className={cn('size-2 rounded-full', STATUS_COLOR[status])} />
            <span className="sr-only">{status} status</span>
          </>
        )}
        <p
          className={cn(
            'text-xs font-medium uppercase tracking-wide',
            accent ? 'text-brand-ink/70' : 'text-muted-foreground'
          )}
        >
          {label}
        </p>
      </div>
      <p
        className={cn(
          'font-display text-4xl font-semibold tracking-tight',
          accent ? 'text-brand-ink' : 'text-foreground'
        )}
      >
        {value}
      </p>
      {delta !== undefined && (
        <p
          className={cn(
            'text-xs mt-2 font-medium',
            delta === 0
              ? 'text-muted-foreground'
              : (delta > 0) !== lowerIsBetter
              ? 'text-emerald-600'
              : 'text-rose-500'
          )}
        >
          {delta > 0 ? '+' : ''}{delta}{deltaLabel ?? ' from yesterday'}
        </p>
      )}
    </div>
  )
}
