import { cn } from '@/lib/utils'

type KpiTileProps = {
  label: string
  value: number | string
  delta?: number
  accent?: boolean
}

export function KpiTile({ label, value, delta, accent }: KpiTileProps) {
  return (
    <div
      className={cn(
        'rounded-3xl p-5',
        accent
          ? 'bg-brand-soft'
          : 'bg-white shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]'
      )}
    >
      <p
        className={cn(
          'text-xs font-medium mb-2 uppercase tracking-wide',
          accent ? 'text-brand-ink/70' : 'text-muted-foreground'
        )}
      >
        {label}
      </p>
      <p
        className={cn(
          'text-4xl font-bold tracking-tight',
          accent ? 'text-brand-ink' : 'text-foreground'
        )}
      >
        {value}
      </p>
      {delta !== undefined && (
        <p
          className={cn(
            'text-xs mt-2 font-medium',
            delta > 0
              ? 'text-emerald-600'
              : delta < 0
              ? 'text-rose-500'
              : 'text-muted-foreground'
          )}
        >
          {delta > 0 ? '+' : ''}{delta} from yesterday
        </p>
      )}
    </div>
  )
}
