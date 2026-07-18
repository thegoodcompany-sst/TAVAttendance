'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { BookOpen, ClipboardCheck, Users } from 'lucide-react'
import { cn } from '@/lib/utils'

const baseItems = [
  { href: '/mobile/classes', label: 'Classes', Icon: BookOpen },
  { href: '/mobile/students', label: 'Students', Icon: Users },
]

export function MobileNav({ isAdmin }: { isAdmin: boolean }) {
  const pathname = usePathname()
  const items = isAdmin
    ? [...baseItems, { href: '/mobile/sign-in', label: 'Sign in', Icon: ClipboardCheck }]
    : baseItems

  return (
    <nav aria-label="Mobile staff navigation" className="fixed inset-x-0 bottom-0 z-40 border-t border-brand/10 bg-white/95 px-3 pb-[max(.65rem,env(safe-area-inset-bottom))] pt-2 shadow-[0_-8px_30px_rgba(25,55,117,.08)] backdrop-blur-xl">
      <div className="mx-auto grid max-w-lg" style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}>
        {items.map(({ href, label, Icon }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`)
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                'mx-1 flex min-h-14 flex-col items-center justify-center gap-1 rounded-2xl text-[11px] font-bold tracking-wide transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand',
                active ? 'bg-brand text-white' : 'text-muted-foreground hover:bg-brand-soft hover:text-brand-ink'
              )}
            >
              <Icon size={21} strokeWidth={active ? 2.6 : 2} />
              {label}
            </Link>
          )
        })}
      </div>
    </nav>
  )
}
