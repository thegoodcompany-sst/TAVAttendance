import Link from 'next/link'

const ACTIONS = [
  { href: '/students', label: 'Students' },
  { href: '/analytics', label: 'Analytics' },
  { href: '/overview', label: 'Overview' },
]

export function QuickActionsCard() {
  return (
    <nav
      aria-label="Quick actions"
      className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-2xl bg-white px-4 py-3 shadow-[0_0_0_1px_rgba(20,33,61,0.08)] sm:justify-end"
    >
      {ACTIONS.map(({ href, label }) => (
        <Link
          key={href}
          href={href}
          prefetch
          className="inline-flex min-h-8 items-center text-sm font-bold text-brand-ink underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring"
        >
          {label}
        </Link>
      ))}
    </nav>
  )
}
