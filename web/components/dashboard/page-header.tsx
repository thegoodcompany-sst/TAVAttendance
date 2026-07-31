import { cn } from '@/lib/utils'

/**
 * Navy band + cream title + marigold underline from the UI draft.
 * One per page, at the top of the content column.
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
        'flex flex-wrap items-end justify-between gap-4 rounded-3xl bg-brand px-6 py-5 shadow-card sm:px-8 sm:py-6',
        className,
      )}
    >
      <div className="min-w-0">
        <h1 className="font-display text-2xl font-semibold tracking-tight text-cream sm:text-3xl">
          {title}
        </h1>
        {subtitle && <p className="mt-1.5 text-sm text-white/75">{subtitle}</p>}
        <div className="mt-3 h-1 w-10 rounded-full bg-accent-marigold" />
      </div>
      {children && <div className="flex-shrink-0">{children}</div>}
    </div>
  )
}
