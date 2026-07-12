'use client'

import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { CalendarDays, BarChart3, LineChart, Users, UserPlus, Flag, TriangleAlert } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Avatar } from './avatar'

const NAV = [
  { href: '/', label: 'Today', Icon: CalendarDays },
  { href: '/overview', label: 'Overview', Icon: BarChart3 },
  { href: '/analytics', label: 'Analytics', Icon: LineChart },
  { href: '/students', label: 'Students', Icon: Users },
  { href: '/users', label: 'Users', Icon: UserPlus },
]

export function Sidebar({ userName, isSuperadmin = false }: { userName: string; isSuperadmin?: boolean }) {
  const pathname = usePathname()
  const nav = isSuperadmin
    ? [
        ...NAV,
        { href: '/feature-flags', label: 'Feature Flags', Icon: Flag },
        { href: '/danger', label: 'Data Wipe', Icon: TriangleAlert },
      ]
    : NAV

  return (
    <aside className="group hidden md:flex flex-col w-[92px] hover:w-[216px] transition-[width] duration-200 ease-in-out min-h-screen bg-white border-r border-border py-5 gap-1 sticky top-0 h-screen flex-shrink-0 overflow-hidden z-20">
      {/* Brand mark */}
      <div className="flex items-center h-10 mb-5 flex-shrink-0 px-[14px]">
        <Image
          src="/tava-logo.png"
          alt="TAVA"
          width={512}
          height={272}
          priority
          style={{ height: '32px', width: 'auto' }}
          className="flex-shrink-0"
        />
      </div>

      {/* Nav */}
      <nav className="flex flex-col gap-1 flex-1 w-full px-2">
        {nav.map(({ href, label, Icon }) => {
          const active = pathname === href
          return (
            <Link
              key={href}
              href={href}
              prefetch
              title={label}
              className={cn(
                'flex items-center h-11 rounded-xl transition-colors w-full pl-[10px] pr-3 gap-3',
                active
                  ? 'bg-brand-soft text-brand-ink'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              )}
            >
              <Icon size={22} className="flex-shrink-0" />
              <span className="whitespace-nowrap text-sm font-medium opacity-0 group-hover:opacity-100 transition-opacity duration-150 delay-[60ms]">
                {label}
              </span>
            </Link>
          )
        })}
      </nav>

      {/* User avatar */}
      <div className="flex items-center h-8 px-[10px] gap-3 flex-shrink-0">
        <Avatar name={userName} size="sm" className="flex-shrink-0" />
        <span className="whitespace-nowrap text-sm font-medium text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity duration-150 delay-[60ms] truncate">
          {userName}
        </span>
      </div>
    </aside>
  )
}
