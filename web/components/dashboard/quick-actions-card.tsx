import Link from 'next/link'
import { Users, LineChart, BarChart3, ArrowUpRight } from 'lucide-react'

const ACTIONS = [
  { href: '/students', label: 'Students', Icon: Users },
  { href: '/analytics', label: 'Analytics', Icon: LineChart },
  { href: '/overview', label: 'Overview', Icon: BarChart3 },
]

export function QuickActionsCard() {
  return (
    <nav
      aria-label="Quick actions"
      className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-2xl bg-white px-4 py-3 shadow-[0_0_0_1px_rgba(20,33,61,0.08)] sm:justify-end"
    >
      {ACTIONS.map(({ href, label, Icon }) => (
        <Link
          key={href}
          href={href}
          prefetch
          className="group inline-flex min-h-8 items-center gap-2 text-sm font-bold text-brand-ink underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring"
        >
          <Icon size={16} className="shrink-0 text-brand/70" aria-hidden="true" />
          <span>{label}</span>
          <ArrowUpRight
            size={13}
            className="shrink-0 text-muted-foreground transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 motion-reduce:transition-none"
            aria-hidden="true"
          />
        </Link>
      ))}
    </nav>
  )
}
