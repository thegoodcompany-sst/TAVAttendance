import type { ComponentProps } from 'react'

import { cn } from '@/lib/utils'

const variants = {
  default: 'border-transparent bg-primary font-bold text-primary-foreground hover:bg-primary/80',
  outline: 'border-border bg-background hover:bg-muted hover:text-foreground',
  destructive: 'border-transparent bg-destructive/10 text-destructive hover:bg-destructive/20 focus-visible:border-destructive/40 focus-visible:ring-destructive/20',
} as const

const sizes = {
  default: 'h-8',
  lg: 'h-9',
} as const

function Button({
  className,
  variant = 'default',
  size = 'default',
  ...props
}: ComponentProps<'button'> & {
  variant?: keyof typeof variants
  size?: keyof typeof sizes
}) {
  return (
    <button
      data-slot="button"
      className={cn(
        "inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-lg border px-2.5 text-sm font-medium transition-all focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
        variants[variant],
        sizes[size],
        className,
      )}
      {...props}
    />
  )
}

export { Button }
