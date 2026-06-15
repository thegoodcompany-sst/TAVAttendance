import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { ImportForm } from './form'

export const dynamic = 'force-dynamic'

export default function ImportStudentsPage() {
  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <Link
        href="/students"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <ArrowLeft size={14} />
        All students
      </Link>

      <div>
        <h1 className="text-2xl font-bold">Import students</h1>
        <p className="text-sm text-muted-foreground mt-0.5">
          Paste CSV rows. Header order:{' '}
          <code className="text-xs bg-muted px-1 py-0.5 rounded">full_name, date_of_birth, school, year_of_study, notes</code>.
          Only <code className="text-xs bg-muted px-1 py-0.5 rounded">full_name</code> is required.
        </p>
      </div>

      <div className="bg-white rounded-3xl p-6 shadow-[0_1px_0_rgba(0,0,0,0.02),0_4px_16px_-4px_rgba(80,60,160,0.08)]">
        <ImportForm />
      </div>
    </div>
  )
}
