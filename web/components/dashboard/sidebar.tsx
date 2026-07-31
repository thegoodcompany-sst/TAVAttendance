'use client'

import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { CalendarDays, BarChart3, LineChart, Users, UserPlus, Flag, TriangleAlert, Trophy, Activity, HeartPulse, MessageSquare, FileText, Download } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Avatar } from './avatar'

const NAV = [
  { href: '/', label: 'Today', Icon: CalendarDays },
  { href: '/overview', label: 'Overview', Icon: BarChart3 },
  { href: '/analytics', label: 'Analytics', Icon: LineChart },
  { href: '/activity', label: 'Activity', Icon: Activity },
  { href: '/students', label: 'Students', Icon: Users },
  { href: '/messages', label: 'Messages', Icon: MessageSquare },
  { href: '/result-slips', label: 'Result Slips', Icon: FileText },
  { href: '/users', label: 'Users', Icon: UserPlus },
]

export function Sidebar({ userName, isSuperadmin = false, showAwards = false, showHealth = false }: { userName: string; isSuperadmin?: boolean; showAwards?: boolean; showHealth?: boolean }) {
  const pathname = usePathname()
  const nav = [
    ...NAV,
    ...(showHealth ? [{ href: '/health', label: 'Health', Icon: HeartPulse }] : []),
    ...(showAwards ? [{ href: '/awards', label: 'Awards', Icon: Trophy }] : []),
    ...(isSuperadmin
      ? [
          { href: '/api/export', label: 'Export all data', Icon: Download },
          { href: '/feature-flags', label: 'Feature Flags', Icon: Flag },
          { href: '/danger', label: 'Data Wipe', Icon: TriangleAlert },
        ]
      : []),
  ]

  return (
    <aside
      className={cn(
        'group/sidebar hidden print:hidden md:flex flex-col',
        'w-[5.75rem] hover:w-[13.5rem]',
        'transition-[width] duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]',
        'min-h-screen bg-white border-r border-border py-5',
        'sticky top-0 h-screen flex-shrink-0 overflow-hidden z-20',
      )}
    >
      {/* Brand mark — left-aligned, never recenters */}
      <div className="flex items-center h-11 mb-5 flex-shrink-0 pl-[1.15rem]">
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

      {/* Nav: min-width keeps full layout so labels don't reflow icons when clipped */}
      <nav className="flex flex-col gap-1 flex-1 w-full min-w-[13.5rem] px-2">
        {nav.map(({ href, label, Icon }) => {
          const active = pathname === href
          const isExport = href === '/api/export'
          const itemClass = cn(
            'group/nav relative flex items-center justify-start gap-3',
            'h-11 w-full max-w-[12.5rem] pl-[0.7rem] pr-3',
            'text-sm font-medium text-left transition-colors duration-200',
            active ? 'text-brand-ink' : 'text-muted-foreground hover:text-brand-ink',
          )
          const highlightClass = cn(
            'pointer-events-none absolute z-0 top-0 left-[0.35rem]',
            'h-11 w-11 rounded-[1.05rem]',
            'transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]',
            'group-hover/sidebar:left-0 group-hover/sidebar:w-full group-hover/sidebar:rounded-[0.85rem]',
            active ? 'bg-brand-soft' : 'bg-transparent group-hover/nav:bg-muted',
          )
          const iconClass = cn(
            'relative z-[1] flex-shrink-0 size-[22px]',
            'scale-125 origin-center transition-transform duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]',
            'group-hover/sidebar:scale-100',
          )
          const labelClass = cn(
            'relative z-[1] whitespace-nowrap',
            'opacity-0 -translate-x-1 pointer-events-none',
            'transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]',
            'group-hover/sidebar:opacity-100 group-hover/sidebar:translate-x-0 group-hover/sidebar:pointer-events-auto',
          )

          return isExport ? (
            <a key={href} href={href} title={label} className={itemClass}>
              <span className={highlightClass} aria-hidden="true" />
              <Icon size={22} className={iconClass} />
              <span className={labelClass}>{label}</span>
            </a>
          ) : (
            <Link key={href} href={href} prefetch title={label} className={itemClass}>
              <span className={highlightClass} aria-hidden="true" />
              <Icon size={22} className={iconClass} />
              <span className={labelClass}>{label}</span>
            </Link>
          )
        })}
      </nav>

      {/* User avatar — same no-reflow clip pattern */}
      <div className="flex items-center h-8 pl-[1.05rem] gap-3 flex-shrink-0 min-w-[13.5rem]">
        <Avatar name={userName} size="sm" className="flex-shrink-0" />
        <span
          className={cn(
            'whitespace-nowrap text-sm font-medium text-muted-foreground truncate',
            'opacity-0 -translate-x-1',
            'transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]',
            'group-hover/sidebar:opacity-100 group-hover/sidebar:translate-x-0',
          )}
        >
          {userName}
        </span>
      </div>
    </aside>
  )
}
