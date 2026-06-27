import Link from 'next/link'
import { UserPlus, Upload, BarChart3, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'

const ACTIONS = [
  { href: '/students/new', label: 'Add student', Icon: UserPlus, primary: true },
  { href: '/students/import', label: 'Import CSV', Icon: Upload, primary: false },
  { href: '/overview', label: 'Overview', Icon: BarChart3, primary: false },
]

export function QuickActionsCard() {
  return (
    <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
      <h2 className="font-semibold mb-4">Quick actions</h2>
      <div className="flex flex-col gap-1">
        {ACTIONS.map(({ href, label, Icon, primary }) => (
          <Link
            key={href}
            href={href}
            prefetch
            className={cn(
              'flex items-center h-11 rounded-xl px-3 gap-3 transition-colors',
              primary
                ? 'bg-brand-soft text-brand-ink hover:brightness-95'
                : 'text-muted-foreground hover:bg-muted hover:text-foreground'
            )}
          >
            <Icon size={20} className="flex-shrink-0" />
            <span className="text-sm font-medium">{label}</span>
            <ChevronRight size={18} className="ml-auto flex-shrink-0 opacity-50" />
          </Link>
        ))}
      </div>
    </div>
  )
}
