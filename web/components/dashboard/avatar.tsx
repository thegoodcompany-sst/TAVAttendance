import { cn } from '@/lib/utils'

const PALETTE = [
  'bg-violet-100 text-violet-700',
  'bg-blue-100 text-blue-700',
  'bg-emerald-100 text-emerald-700',
  'bg-amber-100 text-amber-700',
  'bg-rose-100 text-rose-700',
  'bg-brand-soft text-brand-ink',
]

function colorFor(name: string) {
  const code = name.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0)
  return PALETTE[code % PALETTE.length]
}

type AvatarProps = {
  name: string
  size?: 'sm' | 'md' | 'lg'
  className?: string
}

export function Avatar({ name, size = 'md', className }: AvatarProps) {
  const initials = name
    .split(' ')
    .map(w => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase()

  const sizeClass =
    size === 'sm' ? 'w-8 h-8 text-xs' :
    size === 'lg' ? 'w-12 h-12 text-base' :
    'w-10 h-10 text-sm'

  return (
    <div
      // A11Y-05: announce the full name to screen readers, not the initials.
      role="img"
      aria-label={name}
      className={cn(
        'rounded-full flex items-center justify-center font-semibold flex-shrink-0',
        colorFor(name),
        sizeClass,
        className
      )}
    >
      <span aria-hidden="true">{initials}</span>
    </div>
  )
}
