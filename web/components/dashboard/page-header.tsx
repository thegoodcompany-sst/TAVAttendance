import { cn } from '@/lib/utils'

/**
 * The signature TAVA device: a navy band with a cream display-font title and a
 * short marigold underline — the dashboard echo of the marketing site's
 * full-bleed section bands. One per page, at the top of the content column.
 */
export function PageHeader({
  title,
  subtitle,
  children,
  className,
}: {
  title: string
  subtitle?: string
  children?: React.ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        'bg-brand rounded-3xl px-6 py-5 sm:px-8 sm:py-6 shadow-card flex items-end justify-between gap-4 flex-wrap',
        className,
      )}
    >
      <div className="min-w-0">
        <h1 className="font-display text-2xl sm:text-3xl font-semibold tracking-tight text-[var(--color-primary-foreground)]">
          {title}
        </h1>
        {subtitle && <p className="mt-1.5 text-sm text-white/75">{subtitle}</p>}
        <div className="mt-3 h-1 w-10 rounded-full bg-accent-marigold" />
      </div>
      {children && <div className="flex-shrink-0">{children}</div>}
    </div>
  )
}
