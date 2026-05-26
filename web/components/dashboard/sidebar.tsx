'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { CalendarDays, BarChart3, Users } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Avatar } from './avatar'

const NAV = [
  { href: '/', label: 'Today', Icon: CalendarDays },
  { href: '/overview', label: 'Overview', Icon: BarChart3 },
  { href: '/students', label: 'Students', Icon: Users },
]

export function Sidebar({ userName }: { userName: string }) {
  const pathname = usePathname()

  return (
    <aside className="hidden md:flex flex-col items-center w-[72px] min-h-screen bg-white border-r border-border py-5 gap-1 sticky top-0 h-screen flex-shrink-0">
      {/* Brand mark */}
      <div className="w-10 h-10 rounded-2xl bg-brand flex items-center justify-center text-white font-bold text-lg mb-5 flex-shrink-0">
        T
      </div>

      {/* Nav icons */}
      <nav className="flex flex-col items-center gap-1 flex-1 w-full px-2">
        {NAV.map(({ href, label, Icon }) => {
          const active = pathname === href
          return (
            <Link
              key={href}
              href={href}
              title={label}
              className={cn(
                'w-full flex items-center justify-center h-11 rounded-xl transition-colors',
                active
                  ? 'bg-brand-soft text-brand-ink'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              )}
            >
              <Icon size={20} />
            </Link>
          )
        })}
      </nav>

      {/* User avatar */}
      <Avatar name={userName} size="sm" className="flex-shrink-0" />
    </aside>
  )
}
