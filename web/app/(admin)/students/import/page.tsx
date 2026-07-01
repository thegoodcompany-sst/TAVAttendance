import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { ImportForm } from './form'
import { PageHeader } from '@/components/dashboard/page-header'

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

      <PageHeader title="Import students" />

      <p className="text-sm text-muted-foreground">
        Paste CSV rows. Header order:{' '}
        <code className="text-xs bg-muted px-1 py-0.5 rounded">full_name, date_of_birth, school, year_of_study, notes</code>.
        Only <code className="text-xs bg-muted px-1 py-0.5 rounded">full_name</code> is required.
      </p>

      <div className="bg-white rounded-3xl p-6 shadow-card">
        <ImportForm />
      </div>
    </div>
  )
}
